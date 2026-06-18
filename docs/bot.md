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
contract: **a secret, an endpoint, and the observation→action JSON shape.**

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
| **Auth** | per-bot secret (Vault) via the `bot-gateway` | the human's existing JWT |
| **Wake** | signed webhook to the bot's `webhook_url` | the client's own Realtime observation sub |
| **Use case** | always-on, ranked, hidden-info vs humans | solo / offline vs AI |

They share the spine: the `bots` registry, seating (`add_bot_to_game`), the write
path (`submit_*_bot_action → commit_action` with `'bot'` type), bot observation
rows, outcomes, and ratings. There is **no on-device "warm server"** — a turn is
an event the client already receives, so local bots compute inline; "keep playing
while the app is closed" is by definition a server-side bot.

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

### Identity & per-bot credential (Vault)

The `bots` table gains: `schema_version` (highest game schema the bot supports —
mirrors the human join gate), `webhook_url` (where to wake a server-side bot; NULL
for local), `rated_eligible` (may this bot play rated games). The **per-bot secret
lives in Supabase Vault** (`bot_secret_<id>`), like `serverless_secret` — never a
table column. It is used symmetrically:

- **we → bot** (wake): the trigger signs the payload with the bot's Vault secret so
  the bot trusts the origin.
- **bot → gateway** (action): the bot presents the same secret as a bearer token;
  the gateway verifies it against Vault.

The bot holds **only its own secret + an endpoint**. The all-powerful service role
never leaves our infra (it stays inside the `bot-gateway`). Blast radius of a
leaked bot secret = that one bot's own seats, on its own turn, in games it is
already seated in. Provisioning is `service_role`-only (ops path, no UI):

- `create_bot(p_username, p_display_name, p_bot_type, p_game_type,
  p_schema_version, p_webhook_url, p_rated_eligible)` → inserts the row, generates
  the secret into Vault, returns the **plaintext once**.
- `rotate_bot_key(p_bot_id)` → rotates the Vault secret, returns plaintext once.
- `private.verify_bot_key(p_key)` → resolves a presented key to its `bot_id`.
- `get_bots(p_game_type)` → discovery list for the app (authenticated).

A **local bot** is a `bots` row with **no `webhook_url`** whose `bot_type` matches
a `GameModule.localBot`; a **server-side bot** is a row **with** a `webhook_url` +
Vault secret. The `bot_type` string is the stable handle joining the registry row
to its code; clients never hardcode UUIDs.

### Observation rows for bots

Generalize the `observations` table: `user_id` nullable, add `bot_id` +
`player_index`, XOR check, PK `(game_id, player_index)`. RLS stays
`user_id = auth.uid()`, so bot rows (user_id NULL) are invisible to humans and
Realtime — a feature. `update_all_observations` and `start_game` write a row per
participant. Bots never subscribe; their row is pushed (server-side) or read by a
gated RPC (local).

### Seating — `add_bot_to_game` (service-role, backend only)

`add_bot_to_game(p_game_id, p_bot_id)`, `service_role`-only — bots are seated from
the backend, never the app UI. Takes the `games FOR UPDATE` lock (mirrors
`join_game`) and checks: status `waiting`/`ready`; an open seat exists; **schema
gate** (`games.schema_version <= bots.schema_version`); `game_type` match; not
already seated; **rated guard** — seating a non-`rated_eligible` bot into a rated
game is **rejected** (mirrors the guest rule in `join_game`), never silently
downgraded. Inserts the participant at the next index; flips to `ready` when full.

For solo play, `create_vs_bot_game(...)` (authenticated, `SECURITY DEFINER`)
creates an **unrated** game with the caller as creator, seats the caller + the
named bot, and returns the `game_id` — so the client can start a vs-AI game even
though generic seating is service-role-only.

**v1 seating scope**: solo-vs-bot + explicit host-invite only. Auto-fill
matchmaking (seat a bot when a public game doesn't fill) is **deferred**.

### Action entry — two siblings of `submit_action`

Both mirror `submit_action` (same `FOR UPDATE`, deadline, version, "is it this
seat's turn?" checks; same `game_apply_action → commit_action` with `'bot'` type +
`p_acting_bot_id`). They differ only in who may call and how the seat is
authorized:

- **Server-side**: `submit_bot_action(p_game_id, p_bot_id, p_data,
  p_expected_version)`, `service_role`-only (`REVOKE` from anon/authenticated, like
  `apply_rating_updates`). Authorization is the per-bot key, validated at the
  gateway; this RPC trusts the gateway-resolved `bot_id`.
- **Local**: `submit_local_bot_action(p_game_id, p_bot_id, p_data,
  p_expected_version)`, `authenticated`. Validates `auth.uid()` is a participant in
  this game and `p_bot_id` is a bot participant in the *same* game and it's that
  seat's turn. A human can thus only move a bot in their own game, only on its
  turn.

### `bot-gateway` edge function (server-side bots' only public surface)

A single Deno edge function (same shape as `update-ratings` / `refresh-fcm-token`)
holding `SUPABASE_SERVICE_ROLE_KEY`. The only thing a remote bot talks to, over
plain HTTPS (no Supabase client needed → any language, anywhere):

- Auth: `Authorization: Bearer <bot_secret>` (+ `bot_id`) → `verify_bot_key` → 401
  on mismatch.
- `POST /action { game_id, data, expected_version }` → `submit_bot_action`.

Because wakes carry the observation, **no `/observation` endpoint is needed.**

### Wake — server-side (reuses the turn-notification trigger)

Now that bots have observation rows, the existing `notify_your_turn` trigger fires
for them too. Branch on identity:

- `user_id` set → existing FCM "your turn" push.
- `bot_id` set with a `webhook_url` → read the bot's Vault secret, sign the
  payload (`NEW.data` + `version` + `turn_deadline`), `net.http_post` to
  `webhook_url`. The remote bot verifies the signature, computes, and calls back
  `bot-gateway /action`.

One trigger, two transports. `expire_turn` remains the liveness backstop for an
unreachable bot (hence the timed-game requirement). No separate poller in v1.

### Wake — local (the client's own Realtime sub)

A device can't receive a webhook and must not hold a global bot secret, so local
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
`bool get supportsLocalBots => false;` and `GameBot? localBot(String botType) =>
null;`. The client driver: on a solo game's observation event, for each pending bot
seat → `get_local_bot_observation` → `chooseAction` → `submit_local_bot_action`
(run heavy search via `compute()`; idempotent — server re-checks pending + version).
Server-side bots run no Dart in the engine; their contract is the gateway's
HTTP/JSON shape.

### Ratings

`rated` stays **immutable at creation + reject-violators** (the existing model;
`join_game` already rejects guests from rated games rather than downgrading). Bots
are a **creation-time factor**: `create_vs_bot_game` creates the game unrated, and
`add_bot_to_game` rejects a non-`rated_eligible` bot into a rated game. Ranked bots
(future) = `rated_eligible` + a game policy that opts in.

The rated decision is **derived server-side from one source of truth**: extract the
existing `v_rated := …` logic from `create_game` into `private.derive_rated(...)`,
and expose `preview_game_rating(...)` (authenticated) that calls the same function
so the create dialog can show a live **Rated / Casual** badge without duplicating
the rule in Dart.

## Implementation plan (PR slicing)

- **PR-1 — Foundation.** `bots` columns (`schema_version`, `webhook_url`,
  `rated_eligible`); generalize the `observations` table; fan-out + `start_game`
  write bot rows; `derive_rated` extraction + `preview_game_rating`;
  `add_bot_to_game` + `create_vs_bot_game`; `create_bot` / `rotate_bot_key` /
  `verify_bot_key` / `get_bots` (Vault); GRANT/REVOKE.
- **PR-2 — Server-side bots.** `submit_bot_action` (service-role); the
  `notify_your_turn` bot wake branch (signed webhook); the `bot-gateway` edge
  function + `config.toml`.
- **PR-3 — Local bots.** `submit_local_bot_action` + `get_local_bot_observation`
  (sole-human gate); the `GameBot` contract + `GameModule` opt-in + barrel export;
  repository RPC wrappers + providers; the local-bot driver in `game_screen.dart`;
  the `preview_game_rating` badge + "Play vs AI" entry in the UI.

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
