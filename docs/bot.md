# Bot Support

Status: **implemented** (engine SQL, `bot-gateway` edge function, `LocalBot`
contract + local-bot driver, solo / "Add bot" UI, ratings preview). Pending
a `supabase db reset` to apply the migrations locally. This doc is the contract
spec; the stable parts (the wire contract, the `LocalBot` Dart contract) should move
into `engine_architecture.md` / `game_implementation_guide.md` as they settle.

## Goal

Let anyone **create and wire up a bot easily**, implemented anywhere — a warm
server or a cold serverless function, any language. The engine ships **no bot
logic**; it specifies a stable contract and the seats a bot plugs into. This
cleanly separates bot development from engine and game development behind a thin
contract: **a keypair, an endpoint, and the observation→action JSON shape.**

## The contract

A bot is the same pure function the engine already drives for humans:

```
observation (this seat's projected view)  →  legal action (action data JSON)
```

That is exactly `game_compute_observation` (in) and `game_apply_action` (out).
Everything downstream — `game_apply_action → commit_action → finish_game →
observation fan-out → ratings` — is reused untouched, identical to a human move.

## Two execution models, one spine

|                | Server-side bot | Local bot |
|----------------|-----------------|-----------|
| **Who computes** | a remote function/server | the human's own client |
| **Auth** | per-bot **keypair** — bot signs its action, we verify with its stored public key | the human's existing JWT |
| **Wake** | webhook to the bot's `webhook_url` (origin-authenticated) | the client's own Realtime observation sub |
| **Use case** | always-on, ranked, hidden-info vs humans | solo / offline vs AI |

They share the spine: the `bots` registry, the write path (`submit_*_bot_action →
commit_action` with `'bot'` type), bot observation rows, outcomes, and ratings.
There is **no on-device "warm server"** — a turn is an event the client already
receives, so local bots compute inline; "keep playing while the app is closed" is
by definition a server-side bot.

> **Non-goal: offline play.** "Local bot" means *where the move is computed*, not
> *offline*. The engine is **server-authoritative** — every state transition runs
> server-side (`game_apply_action`), observations are computed server-side, and
> identity/outcomes/ratings live in the DB. A local-bot game still needs the server
> for *every move* (the bot picks its move on-device; the server validates, applies,
> and fans out). True offline solo would require reimplementing the authoritative
> rules in Dart on-device (today they live only in the SQL hooks), making the
> device authoritative, plus local persistence (Drift) and reconnect reconciliation
> — a separate "Offline mode" feature, explicitly **out of scope** here.

## Authorization invariants (engine-enforced, not per-game)

A local bot's move is **computed and submitted by a human's client**, and for
hidden-info games that client is handed the bot's secret view. A client is
untrusted — you cannot prove a client-computed move came from the bot's logic
rather than a human cherry-picking it. Three invariants follow, and they are
enforced structurally (by *which* function may seat a bot), not by ad-hoc checks:

1. **Local bot ⇒ exactly one human in the game.** Two independent reasons, so
   this holds even for a *perfect-information, unrated* game:
   - *Information* (hidden-info games): the driving client is handed the bot's
     secret view, which it must not learn if there's an opponent to exploit it.
   - *Move provenance / collusion* (all games, incl. perfect-info): a local bot is
     an extra seat **one human secretly controls** — they can steer it to help
     themselves or grief the others. It masquerades as neutral AI to the *other*
     humans. The only fix is verifiable provenance, which a client-computed move
     can't provide (verifying it would mean running the bot's policy server-side —
     i.e. making it a server bot).
2. **2+ humans ⇒ server bots only** (corollary of 1).
3. **Rated ⇒ server bots only, no guests.** A rated result needs trusted move
   provenance; a client-driven move isn't trustworthy.

Consequence: the "create a rated game + a local bot, then let a human join and
cheat" scenario is **impossible by construction** — see *Seating* below. These are
universal; what *is* per-game is whether solo play is offered at all and with
how many bots (see *Solo play UX*).

## What already supports it (current state)

- `participants.bot_id`, `actions.bot_id` (`type = 'bot'`), `game_outcomes.bot_id`
  exist; identity `CHECK` constraints encode the human-XOR-bot rule.
- The `bots` registry and the `get_players` UNION resolve bot identities like
  humans — `GamePlayer.type` carries the distinction end-to-end, so the UI renders
  a bot seat with no special-casing.
- `commit_action` accepts `p_acting_bot_id` and a `'bot'` action type.
- `expire_turn` / `expire_all_turns` are **seat-agnostic** — they operate on
  `pending_players` indices and emit `'system'` timeout actions, never assuming a
  human actor. So an unreachable server-side bot auto-resolves at the deadline:
  the game can never hang. Consequence: **server-side bot games must be timed.**
- Ratings already model bot participation.

## The two gaps this closes

1. **Action entry point.** `submit_action` hard-requires `auth.uid()` to be a
   human participant (`require_participant`). Bots need sibling entries that
   resolve the seat by `bot_id`.
2. **Observation delivery.** The `observations` table is human-only
   (`user_id NOT NULL`, PK `(game_id, user_id)`; the fan-out and `start_game`
   filter `WHERE user_id IS NOT NULL`), so **bots have no observation row**. We
   close this by **generalizing the table to store a row per participant** (human
   or bot). This is the key simplification: it makes the bot wake fall out of the
   existing turn-notification trigger, and gives **wake-with-observation for free**
   (the trigger ships the freshly-computed row). No compute-on-demand RPC, no pull
   fallback.

## Design

### Identity & authentication (asymmetric action, HMAC wake)

The `bots` table gains: `schema_version` (highest game schema the bot supports —
mirrors the human join gate), `webhook_url` (where to wake a server-side bot; NULL
for local), `rated_eligible` (may this bot play rated games), and `public_key` (the
bot's **public** key — PEM/JWK; NULL for local bots). No private key is ever stored
server-side; the only per-bot secret we keep is a symmetric **wake secret**, and it
lives in **Vault** (under `bot_wake_secret_<bot_id>`), never on the `bots` row.

The two directions use the cheapest authentication that fits where it runs:

- **bot → us (action) — the security boundary — asymmetric.** The bot signs its
  action request (a JWS over `{game_id, bot_id, player_index, version, data, exp}`)
  with **its private key**.
  The `bot-gateway` loads `bots.public_key` for that `bot_id` and verifies the
  signature, then calls `submit_bot_action`. This authenticates the *actor*
  (only the holder of the bot's private key could sign) **and** the *action* (the
  signature covers `data`, so a MITM cannot alter the move). Replay is blocked by
  `version`/`exp` and the pending-seat re-check under the `games FOR UPDATE` lock.
  The private key never leaves the bot; we store only the public half.
- **us → bot (wake) — low-stakes — HMAC.** The trigger signs the wake body with the
  bot's per-bot wake secret and sends `x-wake-signature` (see *Wake* below); the bot
  recomputes the HMAC over the raw body and compares. A Postgres trigger cannot
  practically produce an *asymmetric* signature, and the wake never authorizes a
  move (every move must still pass the bot-signed gateway check above), so a
  symmetric secret is the right trade: a leaked wake secret only lets someone forge
  wakes to that one bot — wasted compute, no game effect.

**Manual setup, no UI** (bots are rare, one-time). The operator generates the
bot's keypair and a random wake secret, inserts one row, and stores the wake secret
in Vault keyed by the new row's id:

```sql
-- server-side bot (is_local = false ⇒ webhook_url + public_key required)
insert into bots (username, display_name, schema_version,
                  is_local, webhook_url, rated_eligible, public_key)
values ('hard_ai', 'Hard AI', 1,
        false, 'https://my-bot.fly.dev/wake', false, '<bot public key PEM>')
returning id;  -- → <bot_id>

-- the bot's wake secret, named by that id (used by send_bot_wake's HMAC)
select vault.create_secret('<random wake secret>', 'bot_wake_secret_<bot_id>');

-- local bot (is_local = true ⇒ no key, no webhook, no wake secret — driven by
-- the human's client)
insert into bots (username, display_name, schema_version, is_local)
values ('easy_ai', 'Easy AI', 1, true);
```

The bot deployment is configured with its **private** key (to sign actions) and a
copy of its **wake secret** (to verify wakes). `get_bots()`
exposes the safe display columns for the solo picker. The `username` is the
stable handle joining the row to its code (local) or deployment (server-side);
clients never hardcode UUIDs. **`is_local` is the authoritative locality flag** —
never inferred from `webhook_url`, so the server-bot auth scheme can evolve freely;
a `CHECK` keeps the transport columns consistent with it (local ⇒ neither
`webhook_url` nor `public_key`; server ⇒ both). A **local bot** is an `is_local` row
whose `username` matches a `GameModule.localBots` entry (`LocalBot.username`); a
**server-side bot** has `is_local = false`. The all-powerful service role never
leaves the `bot-gateway`.

#### Many personas from one implementation (N:1)

Identity (`username`/`id`) names the bot; **`config` (a `jsonb` column) parameterizes
it** — so one implementation backs many distinct, separately-rated personas with no
code change, and there is no behaviour-classifier string column.

- **Server bots:** point several rows at the **same `webhook_url`** with distinct
  `username`s and different `config`. The wake payload carries `bot_id`, `username`,
  and `config`, so the endpoint self-configures per persona. (You can also ignore
  `config` and key off `bot_id` in the worker's own config — the engine doesn't care.)
- **Local bots:** register several configured instances of one `LocalBot` class in
  `localBots`, e.g. `MinimaxBot(username: 'hard_ai', depth: 5)`. The constructor is
  the usual way to parameterize. The DB `config` of the *matching* row is *also*
  handed to `chooseAction` (for local bots only — a server bot's config never leaves
  the server), so a single instance can instead be tuned from the row. Each persona
  still needs its own `bots` row (same `username`) to appear in the catalog.

#### One identity, many seats (filling a multiplayer game)

A single bot identity (one `bots` row) may occupy **several seats of the same
game** — e.g. one human + one friend + the same `poker_ai` filling the other four
seats of a 6-player game. No duplicate rows, no per-seat usernames.

Seats are addressed by `(game_id, player_index)`, not by `bot_id`: every seat has
its own observation row and fires its own wake carrying that seat's `player_index`;
the bot echoes `player_index` in its signed action, and `submit_bot_action`
validates and acts on exactly that seat. The seats are fully independent
`observation → action` calls — one seat never sees another's hidden state, even
when they are the same identity.

**Ratings** treat each seat as an **independent result** for the identity, applied
in seat order to a running rating (the `update-ratings` function chains them; a
seat is only rated against the *other* distinct identities, never against the
identity's own other seats). Both a strong and a weak seat-result thus contribute,
which is the right signal for a bot's skill. The one accepted caveat: results from
the same game are correlated, so the identity's uncertainty (σ) shrinks a little
faster than from truly separate games — immaterial for bot calibration.

### Observation rows for bots

Generalize the `observations` table: `user_id` nullable, add `bot_id` +
`player_index`, XOR check, PK `(game_id, player_index)`. RLS stays
`user_id = auth.uid()`, so bot rows (user_id NULL) are invisible to humans and
Realtime — a feature. `update_all_observations` and `start_game` write a row per
participant. Bots never subscribe; their row is pushed (server-side) or read by a
gated RPC (local).

### Seating — two paths, each enforcing one slice of the invariants

**Solo — `create_solo_game(p_bot_ids UUID[], …config)`** (authenticated,
`SECURITY DEFINER`). The solo play constructor, generalized to N bots and a
mix of local + server:
- Creates the game with the caller as the **sole** human, **forced unrated**.
- Validates each bot: schema-compatible, and **if the caller is
  anonymous, every bot must be local** (`is_local`) — server bots cost
  real per-move compute and are an abuse surface, so they are off-limits to guests.
- **Timing partitions the bot class.** A timer is a turn-deadline backstop for an
  actor that might not respond: a **server bot needs one** (its endpoint may be
  unreachable — `expire_turn` backstops a dead bot), while a **local bot must be
  untimed** (it is driven by the present human's client, so it needs no backstop
  and must not lose a turn merely because the human navigated away). So
  `create_solo_game` requires **server bots ⇒ timed** and **local bots ⇒ untimed**
  — which also makes a local+server mix impossible (exactly one bot class per
  game).
- Seats the human + all bots, then runs `start_game` internally → the game is
  **full and active in one shot**. Because it is never in a joinable state, **no
  second human can ever join** (invariant 1 holds with no extra guard). Local seats
  are driven by this client; server seats by their webhooks.

**Multiplayer fill — `add_bot_to_game(p_game_id, p_bot_id)`** (authenticated,
**creator-only** — the host's waiting-room "Add bot" button, like `start_game` /
`cancel_game`). `games FOR UPDATE` (mirrors `join_game`), then: caller is
`games.created_by`; **rejects local bots** (`is_local` → invariant 2);
**rejects anonymous callers** (server bots cost per-move compute, like the guest
rule on `create_solo_game`); status `waiting`/`ready`; open seat; **schema gate**
(`games.schema_version <= bots.schema_version`); not already
seated; **rated guard** — a non-`rated_eligible` bot into a rated game is rejected
(invariant 3), never downgraded. Inserts at the next index; flips to `ready` when
full. The creator check and the seat/guard logic split into a private
`seat_server_bot(...)` helper so the deferred matchmaking auto-fill can call it via
service-role without the creator check.

So local bots are reachable **only** via `create_solo_game` (sole-human, unrated,
atomic start); there is no code path that places a local bot into a rated or
multi-human game. `join_game` is unchanged — a solo game is created full, so it
already rejects late joiners.

**v1 seating scope**: solo (`create_solo_game`) + creator-driven server-bot fill of
a multiplayer waiting game (`add_bot_to_game`). Auto-fill matchmaking (seat a server
bot when a *public* game doesn't fill, no host action) is **deferred** but reuses
`private.seat_server_bot`.

### Action entry — two siblings of `submit_action`

Both mirror `submit_action` (same `FOR UPDATE`, deadline, version, "is it this
seat's turn?" checks; same `game_apply_action → commit_action` with `'bot'` type +
`p_acting_bot_id`). They differ only in who may call and how the seat is
authorized:

- **Server-side**: `submit_bot_action(p_game_id, p_bot_id, p_player_index, p_data,
  p_expected_version)`, `service_role`-only (`REVOKE` from anon/authenticated, like
  `apply_rating_updates`). The actor is authenticated by the bot's signature, which
  the gateway verifies against `bots.public_key`; this RPC trusts the
  gateway-resolved `bot_id` and validates that it holds `p_player_index` (a bot may
  hold several seats, so the seat is named explicitly rather than resolved from
  `bot_id`).
- **Local**: `submit_local_bot_action(p_game_id, p_player_index, p_data,
  p_expected_version)`, `authenticated`. Validates `auth.uid()` is a participant,
  the seat is a **local** bot (`is_local` — a server bot can be driven *only* by the
  gateway, never a client), the game is **sole-human**, and (in `apply_seat_action`)
  it is that seat's turn at the expected version. The local-bot/sole-human gates are
  the security boundary: without them, a participant in a multi-human or rated game
  containing a server bot could drive — and front-run — the opponent bot. A human
  can thus only move a *local* bot, in their own *solo* game, on its turn.

### `bot-gateway` edge function (server-side bots' only public surface)

A single Deno edge function (same shape as `update-ratings` / `refresh-fcm-token`)
holding `SUPABASE_SERVICE_ROLE_KEY`. The only thing a remote bot talks to, over
plain HTTPS (no Supabase client needed → any language, anywhere):

- `POST /action { payload, signature }`, where `payload` is the signed JSON
  `{ game_id, bot_id, player_index, version, data, iat }`. The gateway loads
  `bots.public_key` for `bot_id`, **verifies the signature** over the canonical
  payload (Deno's built-in `SubtleCrypto`, e.g. Ed25519/ES256) — 401 on mismatch —
  then calls `submit_bot_action`.

Verification needs no stored secret (only the public key) and covers the action
payload itself. Because wakes carry the observation, **no `/observation` endpoint
is needed.**

We verify in the edge function rather than in-database deliberately: in-DB
Ed25519 verification would need `pgsodium`, which Supabase has marked **pending
deprecation and discourages for new use** — so the gateway (Deno `SubtleCrypto`,
first-class Ed25519/ECDSA) is the durable home for verification. **Platform**:
keep it as a **Supabase Edge Function** for now — it is co-located with the DB (a
Cloudflare Worker would add a network hop to Supabase per call) and is *not* on a
human's critical path (the bot calls it, after spending its own compute), so its
cold start is immaterial. `eigeninteractive-web` (Cloudflare Workers) stays the
home for any future public surface (e.g. an asymmetric-signed wake), but we do not
split infra prematurely.

### Wake — server-side (reuses the turn-notification trigger)

Now that bots have observation rows, the existing `notify_your_turn` trigger fires
for them too. Branch on identity:

- `user_id` set → existing FCM "your turn" push.
- `bot_id` set with a `webhook_url` → `net.http_post` the payload to `webhook_url`:
  `{ game_id, bot_id, player_index, username, config, observation, version,
  pending_players, turn_deadline }` (`player_index` names the seat — one identity
  may hold several; `username`/`config` let one deployment serve many personas —
  see N:1 above). The bot verifies the signature (see below), computes from the
  observation **in the payload**, and calls back `bot-gateway /action` with a
  signed action.

One trigger, two transports. `expire_turn` remains the liveness backstop for an
unreachable bot (hence the timed-game requirement). No separate poller in v1.

### Bot server — reference implementation (what a server bot must have & do)

A server bot is any HTTPS service, in any language. The engine never runs its code
and imposes no framework — only the two-message protocol below. What it **must
have**:

- **An Ed25519 keypair.** The private key stays on the server (signs actions); the
  raw 32-byte **public** key, base64-encoded, goes on the `bots.public_key` row.
- **A copy of its wake secret** — the same random string stored in Vault as
  `bot_wake_secret_<bot_id>` (verifies wakes).
- **Its `bot_id`** (the row's UUID, echoed in every action) and the **gateway URL**:
  `https://<project-ref>.supabase.co/functions/v1/bot-gateway` (`verify_jwt = false`,
  so no Supabase auth header is needed).
- **A public HTTPS endpoint** at the row's `webhook_url`.

What it **must do** on each wake:

1. **Verify the wake.** Read `x-wake-signature`; compute base64 `HMAC-SHA256(rawBody,
   wake_secret)` over the **raw request bytes** (do not re-serialise the parsed
   JSON); reject (and stop) on a non-constant-time-equal mismatch.
2. **Parse** the body `{ game_id, bot_id, player_index, version, observation,
   turn_deadline, … }` and **compute a legal move** for `player_index` from
   `observation`. One identity may hold several seats — treat each wake's
   `player_index` independently; never carry state between seats.
3. **Sign the action.** Build the exact JSON string `payload = {"game_id","bot_id",
   "player_index","version","data","iat"}` (`data` = your move, `iat` = unix
   seconds); Ed25519-sign its UTF-8 bytes; base64 the signature.
4. **Submit** `POST {payload, signature}` to the gateway **before `turn_deadline`**
   (else the seat times out). Handle the reply: `200` committed; `409` a benign race
   (the turn was already taken or the version moved) — drop it; `401` your signature
   or registration is wrong — fix provisioning. The wake itself is fire-and-forget
   (pg_net ignores your HTTP status), so all that matters is the gateway call.

A minimal Node (18+, built-in `crypto`) server — the whole contract in ~40 lines:

```js
import { createServer } from "node:http";
import { createHmac, sign, timingSafeEqual, createPrivateKey } from "node:crypto";

const BOT_ID      = process.env.BOT_ID;
const WAKE_SECRET = process.env.WAKE_SECRET;                  // matches Vault
const GATEWAY     = process.env.GATEWAY_URL;                  // …/functions/v1/bot-gateway
const PRIVATE_KEY = createPrivateKey(process.env.PRIVATE_KEY_PEM); // Ed25519

createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", async () => {
    const raw = Buffer.concat(chunks);                        // sign over the RAW bytes

    // 1. Verify the wake HMAC (constant-time).
    const expected = createHmac("sha256", WAKE_SECRET).update(raw).digest("base64");
    const got = req.headers["x-wake-signature"] ?? "";
    const a = Buffer.from(expected), b = Buffer.from(got);
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      res.writeHead(401).end(); return;
    }
    res.writeHead(200).end();                                 // ack fast; act below

    // 2. Decide a move for THIS seat.
    const wake = JSON.parse(raw.toString("utf8"));
    const data = chooseMove(wake.observation, wake.player_index); // your AI

    // 3. Sign the action payload.
    const payload = JSON.stringify({
      game_id: wake.game_id, bot_id: BOT_ID, player_index: wake.player_index,
      version: wake.version, data, iat: Math.floor(Date.now() / 1000),
    });
    const signature = sign(null, Buffer.from(payload), PRIVATE_KEY).toString("base64");

    // 4. Submit before turn_deadline.
    const r = await fetch(GATEWAY, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ payload, signature }),
    });
    if (!r.ok) console.warn("gateway rejected:", r.status, await r.text());
  });
}).listen(8080);
```

Register the matching public key once (raw 32-byte Ed25519, base64) — e.g. from the
keypair's JWK `x` (base64url → base64), or `openssl pkey -pubout -outform DER` and
base64 the trailing 32 bytes — into `bots.public_key`, and store `WAKE_SECRET` in
Vault as `bot_wake_secret_<bot_id>`. Nothing else is required: no Supabase client,
no database access, no polling.

**Wake signature.** The action signature (above) is the security boundary, so the
wake only needs a low-stakes authentication — a forged wake can at most waste a
bot's compute. Postgres cannot easily produce an *asymmetric* signature inside the
trigger, so `send_bot_wake` HMAC-SHA256s the exact JSON body with the bot's
**per-bot wake secret** (Vault: `bot_wake_secret_<bot_id>`) and sends it base64 in
the `x-wake-signature` header. The bot recomputes the HMAC over the raw request
body with its copy of the same secret and rejects on mismatch. The signature covers
the canonical `jsonb` text, which is exactly the bytes pg_net sends, so there is no
re-serialisation ambiguity. The secret is per-bot, not global, and never authorizes
a move; a leak forges wakes to that one bot only. (If zero-shared-secrets is later
required — e.g. third-party bot authors — sign the wake with a system keypair via a
thin `bot-wake` edge-function hop and have bots verify with our published public
key.)

### Wake — local (the client's own Realtime sub)

A device can't receive a webhook and must not hold a bot's private key, so local
bots use what the human client already has: its own observation subscription
carries `pending_players`. When a **bot** seat (per `PlayersContext`) appears
pending in a **solo** game, the client drives it. No new wake infra.

### Local bots in hidden-information games (e.g. Stratego)

The constraint for local bots is **not** "perfect information" — it's "**is there a
human to cheat against?**" In a **solo** game (one human, the rest bots), there is
none: peeking at the bot's hidden state only spoils the player's own (unrated)
game, exactly like a single-player offline engine. So:

- Perfect-info, any roster → local OK (nothing hidden to leak).
- **Hidden-info, solo vs bot, unrated → local OK** (no human to cheat). ← Stratego.
- Hidden-info **with human opponents** → server-side only.

The client needs the bot seat's *full* observation to run the AI, delivered by a
gated RPC: `get_local_bot_observation(p_game_id, p_player_index)` (authenticated).
The gate is the security boundary, server-enforced: caller is a participant, the
target is a **local** bot in the same game, and **every other participant is a bot**
(the caller is the sole human). It refuses for a server bot, or if a second human is
present — that is the *only* place the engine ever reveals a bot's hidden view to a
client.

### Dart / engine contract (local bots) — `localBots` is the *whole* surface

The implementor's only bot declaration is the **local bot logic they wrote**.
Everything else (server-bot availability, whether solo play is offered, opponent
counts, difficulties, local/server mix) is **derived** — see below.

```dart
// Generic over the same <observation, action, config> triple as BaseEngine, so a
// bot is written and typed exactly like the game's engine.
abstract class LocalBot<TObservationData, TActionData, TConfigData> {
  String get username; // matches bots.username
  /// Decide the bot seat's move from its (typed) observation, returning the game's
  /// typed action — infra serialises it through BaseEngine.serializeAction, the same
  /// seam the human path uses. [config] is the matching bots.config row (empty when
  /// unset) — for DB-tuned personas; ignore it if parameterized in the constructor.
  FutureOr<TActionData> chooseAction({
    required BaseEngine<TObservationData, TActionData, TConfigData> engine,
    required TObservationData observation,
    required int botSeatIndex,
    required Map<String, dynamic> config,
  });
}
```

The action half mirrors the observation half: `BaseEngine.parseObservation` turns
JSON into the typed observation a bot reads, and `BaseEngine.serializeAction` turns
the typed action a bot (or the human content widget) returns back into the `p_data`
JSON the `game_apply_action` hook consumes — one codec, one shape, every producer.

```dart
// On GameModule — the entire bot contract surface. Default empty ⇒ no local bots,
// no boilerplate, nothing to declare. Adding bots is never required.
List<LocalBot> get localBots => const [];
```

We deliberately do **not** expose a "supports local/server bots" flag or a
`SoloPlaySpec`:
- *Local-bot support* = simply *whether `localBots` is non-empty*. Presence is the
  declaration.
- *Server-bot support* is **not a module concern at all** — server bots are
  deployment data (rows + live endpoints) that come and go without an app release,
  discovered at runtime via `get_bots`. A module flag would lie in both directions.
- *Solo-play* (offering, counts, difficulties) is derivable, so a `SoloPlaySpec`
  would only duplicate other sources of truth and drift from them.

**Local logic lives in the game package, not the engine** — a TicTacToe minimax is
meaningless to Poker. The engine owns only the `LocalBot` *contract* + the wiring
(driver, RPCs, picker); the game's `lib/game/` provides the implementations,
exactly parallel to `GameModule` / `BaseEngine`.

The **local-bot driver** only ever runs in a solo game: on each observation event,
for every pending **local** bot seat (one whose `username` matches a `localBots`
entry — a server bot has no matching entry, so it is skipped) →
`get_local_bot_observation` →
`chooseAction` → `submit_local_bot_action` (heavy search via `compute()`;
idempotent — server re-checks pending + version). Server-bot seats in the same solo
game are ignored by the driver (their webhook drives them). Setup phases (e.g.
Stratego piece placement) are ordinary in-game actions handled by the same loop.

**Resolving a bot seat — two cached layers, no per-game join.** Participants are
ephemeral, per-game rows read straight from the table (RLS-gated), carrying only
ids + seat + type — there is **no `get_participants` RPC**. A bot seat's reference
data is resolved by id from two separate caches, mirroring how a human seat is:
- *Identity* ("player sense") — `get_players` → `PlayerInfo` (username, display
  name, avatar), cached per-id; this is what the UI renders and where the driver
  reads `username` to match `localBots`. Works uniformly for humans and bots.
- *Capability* ("bot sense") — `get_bots` → the `BotInfo` **catalog**, a `keepAlive`
  cached list (rarely changes), where the driver reads the seat's `config`. `config`
  is exposed for local bots only; a server bot's stays server-side.

Keeping these distinct avoids conflating ephemeral game state with static reference
data, and keeps `PlayerInfo` free of bot-only operational fields.

### Versioning bot logic

Both kinds reuse the **schema gate**, just from different "highest supported schema"
sources — no separate bot-versioning machinery:
- **Local**: the logic ships *in the app build*, so it is versioned with the app /
  the module's `schemaVersion`. A build may drive a local bot iff
  `module.schemaVersion >= game.schema_version` **and** `localBots` contains that
  `username`. An old build (missing the impl or too old for the schema) simply
  doesn't offer it — graceful, same mechanism as the human join gate.
- **Server**: the logic lives in the operator's deployment, versioned
  independently; the `bots.schema_version` *row* gates which game schemas it may be
  seated into.

### Solo play UX — derived, not declared

The solo picker is a first-class, one-tap entry — **not** "create a game, then add a
bot in the waiting room" — and it is derived entirely from data:

- **Shown** iff a playable *(timing, bot-class)* combination exists
  (`soloPlayAvailableProvider`), honouring the local⇒untimed / server⇒timed
  partition: an **untimed** mode with a usable local bot (a `localBots` entry whose
  schema-compatible `bots` row ships), **or** a **timed** mode with a usable server
  bot (registered, schema-compatible, non-guest). Gating on the timing-aware
  predicate — not merely "a bot exists" — keeps a timed-only game from showing a
  solo-play entry that would open a dead-end picker.
- **Opponent counts** come from the game's existing `creationSpec` /
  `playersForConfig` (1 opponent for a 2-player game; "1 human + N bots" across the
  game's valid counts). The picker renders the game's own `buildCreationConfig`
  (which carries the count for variable-count games, collapsing `playersForConfig`
  to a single value) and adds a generic player selector only when the game still
  exposes a true range (`min < max`).
- **Opponents / labels** are the usable bots' `display_name` — these are
  *personas*, not a difficulty ladder (a build may ship "Aggressive"/"Defensive"
  as easily as "Easy"/"Hard"), so the picker says "choose your opponent", never
  "difficulty". Optional `bots.sort_order` only if deterministic ordering is wanted.

The engine picker (`PlayVsBotDialog`) shows **one selector per opponent seat**
(count − 1 of them), each **defaulting to the first usable bot** — so the common
"all the same opponent" case is zero taps, and the user overrides only the seats
they want different (no separate fill-all step). It shares the New Game dialog's
`TimingSelector`, so a solo game can be untimed or clocked. It then calls
`create_solo_game(bot_ids[], timing…)` and drops the player **straight into the
game** (it started atomically — no waiting room). Every opponent seat is filled
independently, so multiplayer practice ("1 human + 5 bots") needs no special-casing.

**Timing selects the bot class** (the partition above), surfaced by *availability*,
not a warning: an **untimed** game offers **local** bots; a **timed** game offers
**server** bots (and never to guests). Switching timing re-derives the usable list,
and any seat whose bot is no longer usable reverts to the default — so no invalid
combination can reach `create_solo_game`. The picker opens in a mode that actually
has opponents: it inspects the (warm) bot catalog and passes `TimingSelector`'s
`initialKey` — the first untimed mode if a local bot is usable, else the first
timed mode if a server bot is — so it never opens empty. `TimingSelector` itself
stays bot-agnostic; the bot-aware choice lives in the picker.

The other touchpoint is the **host's waiting-room "Add bot"** affordance for a
*multiplayer human* game (e.g. a 6-player poker with 4 humans): the creator picks a
**server** bot to fill an open seat via `add_bot_to_game` (the picker offers only
`rated_eligible` bots when the game is rated; hidden for guest hosts). Automatic
fill of unfilled *public* games (no host action) is the deferred "Quick Match".

### Ratings

`rated` stays **immutable at creation + reject-violators** (the existing model;
`join_game` already rejects guests from rated games rather than downgrading). Bots
are a **creation-time factor**: `create_solo_game` creates the game unrated, and
`add_bot_to_game` rejects a non-`rated_eligible` bot into a rated game. Ranked bots
(future) = `rated_eligible` + a game policy that opts in.

The rated decision is **derived server-side from one source of truth**: extract the
existing `v_rated := …` logic from `create_game` into `private.derive_rated(...)`,
and expose `preview_game_rating(...)` (authenticated) that calls the same function
so the create dialog can show a live **Rated / Casual** badge without duplicating
the rule in Dart.

## Implementation plan (PR slicing)

- **PR-1 — Foundation.** `bots` columns (`schema_version`, `webhook_url`,
  `rated_eligible`, `public_key`); narrow the `bots` RLS / add `get_bots`
  (safe display columns); generalize the `observations` table; fan-out +
  `start_game` write bot rows (factor `start_game`'s core into a helper
  `create_solo_game` can also call); `derive_rated` extraction +
  `preview_game_rating`; `private.seat_server_bot` + `add_bot_to_game`
  (authenticated, creator-only) + `create_solo_game(bot_ids[])` (atomic seat+start,
  unrated, anonymous⇒local-only); GRANT/REVOKE. (No provisioning RPC — bots are
  inserted by hand; identity is one row + a public key, plus a Vault wake secret
  for server bots.)
- **PR-2 — Server-side bots.** `submit_bot_action` (service-role); the
  `notify_your_turn` bot wake branch (`net.http_post` + per-bot HMAC
  `x-wake-signature` header, secret from Vault `bot_wake_secret_<bot_id>`); the
  `bot-gateway` edge function (verifies the bot's signature against
  `bots.public_key`) + `config.toml`; the host's waiting-room **"Add bot"** UI
  (it's only useful once a seated server bot can actually move).
- **PR-3 — Local bots.** `submit_local_bot_action` + `get_local_bot_observation`
  (local-bot + sole-human gate); the `LocalBot` contract (engine) + `GameModule.localBots`
  (game package) + barrel export; repository RPC wrappers + providers; the
  local-bot driver in `game_screen.dart`; the `preview_game_rating` badge + the
  **derived** solo-play entry (shown when a usable bot exists; counts from
  `playersForConfig`; opponents from `get_bots`) in the UI.

Files (engine, dev-phase edit-in-place SQL): `bots` in
`supabase/migrations/20251212144609_create_users_table.sql`; `observations` in
`…/20251217122729_create_observations_table.sql`; RPCs/fan-out in
`…/20260505045425_create_game_infra_functions.sql`; wake in
`…/20260518091300_notification_triggers.sql`; `supabase/functions/bot-gateway/`;
Dart in `lib/core/game/local_bot.dart`, `lib/core/game/game_module.dart`,
`lib/features/game/data/game_repository.dart`,
`lib/features/game/providers/game_providers.dart`,
`lib/features/game/presentation/screens/game_screen.dart`,
`lib/features/game/presentation/widgets/new_game_dialog.dart`,
`lib/eigen_engine.dart`. After each engine SQL change, sync into the app:
`dart run eigen_engine:sync_supabase` then `supabase db reset`.
