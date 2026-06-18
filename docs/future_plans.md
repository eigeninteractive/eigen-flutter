# Future Plans

Designs for features that are **not yet built**. `engine_architecture.md` and
`game_implementation_guide.md` describe the system as it exists today; anything
speculative lives here until it ships, then moves into those docs.

Each entry is a self-contained slice intended to land as its own PR.

---

## Bot Support

Goal: let anyone **create and wire up a bot against this infra very easily**,
implemented anywhere (a server, a serverless function, any language). The engine
does **not** ship bot logic — it specifies a stable contract and the seats a bot
plugs into. Two execution models are supported:

- **Local bot** — the move is computed client-side (e.g. a minimax TicTacToe
  engine in the human player's own app) and submitted on behalf of a bot seat in
  a game the human is already in. Reuses human auth; no new credentials or wake
  infra.
- **Server-side bot** — the bot runs independently of any human client (edge
  function, external worker, etc.), is woken when it is its turn, pulls its own
  observation, and submits an action. Authenticated as itself via a **per-bot
  credential** (not the shared service role).

### The contract

A bot is the same pure function the engine already drives for humans:

```
observation (this seat's projected view)  →  legal action (action data JSON)
```

That is exactly `game_compute_observation` (in) and `game_apply_action` (out).
So "wire up a bot" reduces to giving a remote process (a) its observation and
(b) an authenticated way to submit an action. Everything downstream —
`game_apply_action → commit_action → finish_game → observation fan-out →
ratings` — is reused untouched, identical to a human move.

### What already supports it (current state)

- `participants.bot_id`, `actions.bot_id` (`type = 'bot'`), and
  `game_outcomes.bot_id` exist; the identity `CHECK` constraints encode the
  human-XOR-bot rule.
- The `bots` registry (`bot_type`, `game_type`) and the `get_players` UNION
  resolve bot identities exactly like humans — `GamePlayer.type` carries the
  distinction end-to-end, so the UI renders a bot seat with no special-casing.
- `commit_action` accepts `p_acting_bot_id` and a `'bot'` action type, so the
  write path already records bot moves correctly.
- `expire_turn` / `expire_all_turns` are **seat-agnostic**: they operate on
  `pending_players` indices and emit `'system'` timeout actions, never assuming
  a human actor. An unreachable or crashed server-side bot therefore auto-
  resolves at the turn deadline — a free liveness guarantee, but it means
  **server-side bot games must be timed** (untimed games would hang on a dead
  bot).
- Ratings already model bot participation.

### The two gaps

1. **Action entry point.** `submit_action` is the only entry and it hard-
   requires `auth.uid()` to be a human participant (`require_participant`). Bots
   need sibling entry points that resolve the seat by `bot_id`.
2. **Observation delivery.** _(Not noted in the original analysis.)_ The
   `observations` table is `user_id UUID NOT NULL` (PK `game_id,user_id`), and
   both `update_all_observations` and `start_game` filter
   `WHERE user_id IS NOT NULL`. **Bots have no observation row at all.** Rather
   than persist bot rows (which would pull bots into Realtime/RLS they do not
   need), observations are **computed on demand** for a bot seat via the
   existing hook.

### Design

#### Identity & per-bot credential

Extend the `bots` table (a bot is registered once, then runs anywhere):

- `key_hash TEXT` — bcrypt hash of the bot's API key (`crypt(key, gen_salt('bf'))`
  via `pgcrypto`). Plaintext is shown exactly once at provisioning.
- `key_prefix TEXT` — first few chars of the key, for display/identification.
- `webhook_url TEXT` — where to wake this bot (server-side only; NULL for local).
- `webhook_secret TEXT` — shared secret the bot uses to verify a wake came from
  us (server-side only).

Provisioning is admin/`service_role`-only:

- `create_bot(p_username, p_display_name, p_bot_type, p_game_type, …)` →
  inserts the row, generates the key, returns the **plaintext key once**.
- `rotate_bot_key(p_bot_id)` → new key, returns plaintext once.

The per-bot key is the bot's _only_ secret. The all-powerful service role never
leaves our infra — see the gateway below.

#### Seating — `add_bot_to_game`

`add_bot_to_game(p_game_id UUID, p_bot_id UUID)`, callable by `authenticated`.
The "second entry point that targets a bot seat" for _seating_ (distinct from
_acting_). Validates the caller is the game's creator/participant, the game is
`waiting`/`ready` with an open seat, the bot's `game_type` matches, and the
bot's schema is compatible; inserts a `participants` row with `bot_id` at the
next `player_index`; transitions to `ready` when full. Mirrors `join_game`'s
seat logic. (UI: an "Add bot" affordance in the lobby / pre-game screen.)

#### Observation — `get_bot_observation`

`get_bot_observation(p_game_id UUID, p_bot_id UUID)`, `service_role`-only.
Resolves the seat by `(game_id, bot_id)` and returns the same shape a human
observation row carries — `data`, `pending_players`, `version`, `turn_deadline`
— by running `game_compute_observation(state, pending, player_index, count,
config, schema_version)` against the latest `game_states` row. No schema change,
no fan-out churn. `version` is returned so the caller can pass it straight back
as the optimistic lock on submit.

#### Action — two siblings of `submit_action`

Both mirror `submit_action` (same lock, deadline, version, "is it this seat's
turn?" checks; same `game_apply_action` → `commit_action` with `'bot'` type and
`p_acting_bot_id`). They differ only in _who may call_ and _how the seat is
authorized_:

- **Server-side**: `submit_bot_action(p_game_id, p_bot_id, p_data,
  p_expected_version)`, `service_role`-only (`REVOKE` from `anon`,
  `authenticated`, like `apply_rating_updates`). Authorization is the per-bot key
  validated at the gateway (below); this RPC trusts that the gateway resolved the
  `bot_id`.
- **Local**: `submit_local_bot_action(p_game_id, p_bot_id, p_data,
  p_expected_version)`, callable by `authenticated`. Validates that
  `auth.uid()` is a participant in this game **and** that the target `p_bot_id`
  is a bot participant in the _same_ game. A human can thus only move a bot in
  their own game, only when it is the bot's turn — no new attack surface beyond
  the (shared, deterministic) bot logic itself. No key, no gateway, no wake.

#### `bot-gateway` edge function (server-side bots' only public surface)

A single Deno edge function, same deployment shape as `update-ratings` /
`refresh-fcm-token`, holding `SUPABASE_SERVICE_ROLE_KEY`. It is the only thing a
remote bot talks to, over plain HTTPS (no Supabase client needed → "any
language, anywhere"):

- Auth: `Authorization: Bearer <bot_api_key>`. The gateway calls
  `verify_bot_key(p_key)` → `bot_id` (bcrypt compare on `key_hash`), or 401.
- `POST /observation { game_id }` → `get_bot_observation(bot_id, game_id)`.
- `POST /action { game_id, data, expected_version }` →
  `submit_bot_action(bot_id, game_id, …)`.

Keeping validation server-side means the bot only ever holds its own key, and we
have one place for auth + rate limiting.

#### Wake mechanism (server-side only)

The observation-change trigger (`notify_your_turn`) never fires for bots (no
rows), so wakes use the bot's registered `webhook_url`:

- **Push**: a trigger after fan-out (on `game_states` insert, or folded into the
  fan-out path) detects any _bot_ seat newly in `pending_players` and
  `net.http_post`s `{game_id, bot_id}` to that bot's `webhook_url`, signed with
  its `webhook_secret` so the bot can trust the origin. The remote bot then calls
  back the gateway (`/observation`, then `/action`).
- **Poll (safety net)**: a `pg_cron` job (mirroring `expire-turns`) re-posts
  wakes for bot seats pending beyond N seconds, covering a dropped `http_post`.
  Idempotent — `submit_bot_action` re-checks pending + version. Beyond that, the
  deadline path (`expire_turn`) is the ultimate backstop for a truly dead bot.

`notify_your_turn` should also gain an explicit bot-seat skip (bots have no
`device_tokens`, so it is a harmless no-op today, but the guard documents intent
and avoids a wasted lookup).

#### Dart / engine contract (local bots)

The engine exposes a small contract the `GameModule` implements so the client can
drive a local bot with the same `BaseEngine` it already ships:

```dart
abstract class GameBot {
  /// Matches bots.bot_type.
  String get botType;

  /// Given this seat's observation, return a legal action's `data` payload.
  FutureOr<Map<String, dynamic>> chooseAction(Observation observation);
}
```

The `GameModule` advertises its local bots (e.g. `GameBot? localBot(String
botType)`). The client, on detecting a bot seat in `pending_players` of a game it
is in, computes the move and submits via `submit_local_bot_action`. Server-side
bots run no Dart in the engine — for them the contract _is_ the gateway's
HTTP/JSON shape, documented here and pinned by the stable observation/action
schemas.

### Suggested PR slicing

- **PR-A — Bot identity & seating.** `bots` credential columns + `create_bot` /
  `rotate_bot_key`, `add_bot_to_game`, and the "add bot" UI. Prerequisite for
  both models. (Credentials are only _consumed_ by server-side bots, but the
  identity belongs here.)
- **PR-B — Local bots.** `submit_local_bot_action`, the `GameBot` contract +
  `GameModule` hook, and the client driver. Cheapest path to a playable
  vs-AI/single-player experience; no edge function, no keys in flight.
- **PR-C — Server-side bots.** `get_bot_observation`, `submit_bot_action`
  (service-role), `verify_bot_key`, the `bot-gateway` edge function, per-bot
  `webhook_url`/`webhook_secret`, the wake trigger + `pg_cron` poller, and the
  `notify_your_turn` bot skip.

---

## Spectating — Finished Public Games (own PR)

Scope intentionally limited to **spectating finished, public games** (replay).
Live spectating is explicitly out of scope: spectating a live hidden-information
game from a second account is a cheating vector, so it is deferred until there
is a per-game policy for it.

`PlayersContext.myPlayerIndex` already reserves `-1` for a spectator, but no
spectator path is wired up yet.

What this PR needs:

- **Server**: relax `get_replay`'s participant check to "participant **or** the
  game is finished and its access is public." It already projects each
  `game_states` row through `game_compute_observation` with
  `p_is_replay = true`, so post-game reveal rules stay the hook's responsibility
  — raw state is never exposed.
- **Client**: a spectator entry point into the existing replay UI from a
  finished public game (lobby/profile), with `myPlayerIndex == -1`. Guard
  against `PlayersContext.me` being called for a spectator.

Not in scope: live/active spectating, delayed feeds, hidden-info live policy.
