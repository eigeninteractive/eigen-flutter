# Bot Support

Status: **designed, not yet built.** This doc is the contract spec and the
implementation plan. Once it ships, the stable parts (the wire contract, the
`GameBot` Dart contract) move into `engine_architecture.md` /
`game_implementation_guide.md`.

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
universal; what *is* per-game is whether "Play vs AI" is offered at all and with
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

### Identity & authentication (mutual asymmetric — no shared secrets)

The `bots` table gains: `schema_version` (highest game schema the bot supports —
mirrors the human join gate), `webhook_url` (where to wake a server-side bot; NULL
for local), `rated_eligible` (may this bot play rated games), and `public_key` (the
bot's **public** key — PEM/JWK; NULL for local bots). There is **no provisioning
RPC and no per-bot secret stored anywhere** — public keys are not sensitive, so the
whole identity is one row.

Authentication uses signatures, not shared secrets, and the two directions are
mirror images:

- **bot → us (action) — the security boundary.** The bot signs its action request
  (a JWS over `{game_id, bot_id, version, data, exp}`) with **its private key**.
  The `bot-gateway` loads `bots.public_key` for that `bot_id` and verifies the
  signature, then calls `submit_bot_action`. This authenticates the *actor*
  (only the holder of the bot's private key could sign) **and** the *action* (the
  signature covers `data`, so a MITM cannot alter the move). Replay is blocked by
  `version`/`exp` and the pending-seat re-check under the `games FOR UPDATE` lock.
  The private key never leaves the bot; we store only the public half.
- **us → bot (wake) — origin check.** The wake carries a header proving it came
  from the game server (see *Wake* below). This is the low-stakes direction: a
  forged wake can only waste a bot's compute — it cannot move a game, because every
  move must pass the bot-signed gateway check above.

**Manual setup, no UI** (bots are rare, one-time). The operator generates a keypair
on the bot side and inserts one row in the Supabase dashboard:

```sql
-- server-side bot
insert into bots (username, display_name, bot_type, game_type,
                  schema_version, webhook_url, rated_eligible, public_key)
values ('hard_ai', 'Hard AI', 'minimax', 'tic_tac_toe', 1,
        'https://my-bot.fly.dev/wake', false, '<bot public key PEM>');

-- local bot (no key, no webhook — driven by the human's client)
insert into bots (username, display_name, bot_type, game_type, schema_version)
values ('easy_ai', 'Easy AI', 'random', 'tic_tac_toe', 1);
```

The bot deployment is configured with its **private** key. `get_bots(p_game_type)`
exposes the safe display columns for the "Play vs AI" picker. The `bot_type` string
is the stable handle joining the row to its code (local) or deployment
(server-side); clients never hardcode UUIDs. A **local bot** is a row with no
`webhook_url`/`public_key` whose `bot_type` matches a `GameModule.localBot`; a
**server-side bot** is a row with both. The all-powerful service role never leaves
the `bot-gateway`.

### Observation rows for bots

Generalize the `observations` table: `user_id` nullable, add `bot_id` +
`player_index`, XOR check, PK `(game_id, player_index)`. RLS stays
`user_id = auth.uid()`, so bot rows (user_id NULL) are invisible to humans and
Realtime — a feature. `update_all_observations` and `start_game` write a row per
participant. Bots never subscribe; their row is pushed (server-side) or read by a
gated RPC (local).

### Seating — two paths, each enforcing one slice of the invariants

**Solo — `create_solo_game(p_bot_ids UUID[], …config)`** (authenticated,
`SECURITY DEFINER`). The "Play vs AI" constructor, generalized to N bots and a
mix of local + server:
- Creates the game with the caller as the **sole** human, **forced unrated**.
- Validates each bot: `game_type` match, schema-compatible, and **if the caller is
  anonymous, every bot must be local** (`webhook_url IS NULL`) — server bots cost
  real per-move compute and are an abuse surface, so they are off-limits to guests.
- Seats the human + all bots, then runs `start_game` internally → the game is
  **full and active in one shot**. Because it is never in a joinable state, **no
  second human can ever join** (invariant 1 holds with no extra guard). Local seats
  are driven by this client; server seats by their webhooks.

**Multiplayer fill — `add_bot_to_game(p_game_id, p_bot_id)`** (authenticated,
**creator-only** — the host's waiting-room "Add bot" button, like `start_game` /
`cancel_game`). `games FOR UPDATE` (mirrors `join_game`), then: caller is
`games.created_by`; **rejects local bots** (`webhook_url IS NULL` → invariant 2);
**rejects anonymous callers** (server bots cost per-move compute, like the guest
rule on `create_solo_game`); status `waiting`/`ready`; open seat; **schema gate**
(`games.schema_version <= bots.schema_version`); `game_type` match; not already
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

- **Server-side**: `submit_bot_action(p_game_id, p_bot_id, p_data,
  p_expected_version)`, `service_role`-only (`REVOKE` from anon/authenticated, like
  `apply_rating_updates`). The actor is authenticated by the bot's signature, which
  the gateway verifies against `bots.public_key`; this RPC trusts the
  gateway-resolved `bot_id`.
- **Local**: `submit_local_bot_action(p_game_id, p_bot_id, p_data,
  p_expected_version)`, `authenticated`. Validates `auth.uid()` is a participant in
  this game and `p_bot_id` is a bot participant in the *same* game and it's that
  seat's turn. A human can thus only move a bot in their own game, only on its
  turn.

### `bot-gateway` edge function (server-side bots' only public surface)

A single Deno edge function (same shape as `update-ratings` / `refresh-fcm-token`)
holding `SUPABASE_SERVICE_ROLE_KEY`. The only thing a remote bot talks to, over
plain HTTPS (no Supabase client needed → any language, anywhere):

- `POST /action { game_id, bot_id, data, version, signature }`. The gateway loads
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
- `bot_id` set with a `webhook_url` → `net.http_post` the payload (`NEW.data` +
  `version` + `turn_deadline`) to `webhook_url`. The bot verifies the origin (see
  below), computes from the observation **in the payload**, and calls back
  `bot-gateway /action` with a signed action.

One trigger, two transports. `expire_turn` remains the liveness backstop for an
unreachable bot (hence the timed-game requirement). No separate poller in v1.

**Wake origin check.** The action signature (above) is the security boundary, so
the wake only needs a low-stakes origin proof — a forged wake can at most waste a
bot's compute. Postgres cannot easily produce an asymmetric signature inside the
trigger, so the wake carries a **single global shared secret** header
(`x-webhook-secret`, stored in Vault — the same `serverless_secret` mechanism the
FCM/ratings triggers already use); the bot compares it. This is the *only* shared
secret in the system, it is not per-bot, and it never authorizes a move. (If
zero-shared-secrets is later required — e.g. third-party bot authors — sign the
wake with a system keypair via a thin `bot-wake` edge-function hop and have bots
verify with our published public key.)

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
gated RPC: `get_local_bot_observation(p_game_id, p_bot_id)` (authenticated). The
gate is the security boundary, server-enforced: caller is a participant, target is
a bot in the same game, and **every other participant is a bot** (the caller is the
sole human). It refuses if a second human is present — that is the *only* place the
engine ever reveals a bot's hidden view to a client.

### Dart / engine contract (local bots)

```dart
abstract class GameBot {
  String get botType; // matches bots.bot_type
  /// Decide the bot seat's move from its observation.
  FutureOr<Map<String, dynamic>> chooseAction(Observation observation,
      int botSeatIndex);
}
```

`GameModule` gains safe-default opt-ins so existing games are unaffected:
`GameBot? localBot(String botType) => null;` (the local bot logic) and
`SoloPlaySpec? get soloPlay => null;` (below).

The **local-bot driver** is simple under the invariants — it only ever runs in a
solo game: on each observation event, for every pending **local** bot seat (one
whose `bot_type` has a `localBot` impl *and* whose row has no `webhook_url`) →
`get_local_bot_observation` → `chooseAction` → `submit_local_bot_action` (heavy
search via `compute()`; idempotent — server re-checks pending + version).
Server-bot seats in the same solo game are ignored by the driver (their webhook
drives them). Setup phases (e.g. Stratego piece placement) are ordinary in-game
actions handled by the same loop. Server-side bots run no Dart in the engine;
their contract is the gateway's HTTP/JSON shape.

### Solo play UX (`SoloPlaySpec`)

"Play vs AI" is a first-class, one-tap entry — **not** "create a game, then add a
bot in the waiting room". The `GameModule` declares it:

```dart
/// Null → no "Play vs AI" for this game (implementor's choice, e.g. a game with
/// no good bot). Otherwise drives the practice picker.
SoloPlaySpec? get soloPlay => null;
```

`SoloPlaySpec` declares the opponent-count options (1 bot for Chess/Stratego/RPS;
"1 human + N bots" for multiplayer games like Poker / Exploding Kittens) and the
available bots/difficulties (resolved against `get_bots(game_type)`). The app shows
a **"Play vs AI"** entry next to "New Game"/"Join" *only when* `soloPlay != null`;
tapping it shows a small difficulty/opponent-count picker, then calls
`create_solo_game(...)` and drops the player **straight into the game** (it started
atomically — no waiting room). Multiplayer games are free to offer it (1 human + N
bots) or not.

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
  unrated, anonymous⇒local-only); GRANT/REVOKE. (No provisioning RPC, no Vault
  per-bot — bots are inserted by hand; identity is one row + a public key.)
- **PR-2 — Server-side bots.** `submit_bot_action` (service-role); the
  `notify_your_turn` bot wake branch (`net.http_post` + global `x-webhook-secret`
  origin header); the `bot-gateway` edge function (verifies the bot's signature
  against `bots.public_key`) + `config.toml`; the host's waiting-room **"Add bot"**
  UI (it's only useful once a seated server bot can actually move).
- **PR-3 — Local bots.** `submit_local_bot_action` + `get_local_bot_observation`
  (sole-human gate); the `GameBot` contract + `GameModule.localBot`/`soloPlay`
  opt-ins + barrel export; repository RPC wrappers + providers; the local-bot driver
  in `game_screen.dart`; the `preview_game_rating` badge + the `SoloPlaySpec`-driven
  "Play vs AI" entry in the UI.

Files (engine, dev-phase edit-in-place SQL): `bots` in
`supabase/migrations/20251212144609_create_users_table.sql`; `observations` in
`…/20251217122729_create_observations_table.sql`; RPCs/fan-out in
`…/20260505045425_create_game_infra_functions.sql`; wake in
`…/20260518091300_notification_triggers.sql`; `supabase/functions/bot-gateway/`;
Dart in `lib/core/game/game_bot.dart`, `lib/core/game/game_module.dart`,
`lib/features/game/data/game_repository.dart`,
`lib/features/game/providers/game_providers.dart`,
`lib/features/game/presentation/screens/game_screen.dart`,
`lib/features/game/presentation/widgets/new_game_dialog.dart`,
`lib/eigen_engine.dart`. After each engine SQL change, sync into the app:
`dart run eigen_engine:sync_supabase` then `supabase db reset`.
