# Future Plans

Designs for features that are **not yet built**. `engine_architecture.md` and
`game_implementation_guide.md` describe the system as it exists today; anything
speculative lives here until it ships, then moves into those docs.

Each entry is a self-contained slice intended to land as its own PR.

---

## Bot Support

Goal: support both **local bots** (move computed client-side, e.g. a minimax
TicTacToe engine in the human player's app) and **server-side bots** (the bot
runs in a compute engine — an edge function or external worker holding the
service role — and acts independently of any human client). This entry only
records the seam; no runner is implemented.

### What already supports it (current state)

The schema and identity stack are bot-ready today:

- `participants.bot_id`, `actions.bot_id` (`type = 'bot'`), and
  `game_outcomes.bot_id` exist; the identity `CHECK` constraints encode the
  human-XOR-bot rule.
- The `bots` registry (`bot_type`, `game_type`) and the `get_players` UNION
  resolve bot identities exactly like humans — `GamePlayer.type` carries the
  distinction end-to-end, so the UI renders a bot seat with no special-casing.
- `commit_action` accepts a `p_acting_bot_id` and `'bot'` action type, so the
  write path already records bot moves correctly.
- Ratings already model bot participation.

### The one missing seam

`submit_action` is the only action entry point and it requires `auth.uid()` to
be a human participant (`require_participant`). Adding bots means a **second
entry point** that targets a _bot_ seat — everything downstream
(`game_apply_action` → `commit_action` → observation fan-out) is reused
unchanged:

- **Server-side**: a `service_role`-only RPC, e.g.
  `submit_bot_action(p_game_id, p_bot_id, p_data, p_expected_version)`, callable
  only by the bot runner. Mirrors `submit_action` but resolves the participant
  by `bot_id` and passes `p_acting_bot_id` to `commit_action`. REVOKE from
  `anon`/`authenticated` like `store_fcm_access_token`. A trigger on observation
  fan-out (or a pg_cron poller) wakes the runner when a bot seat enters
  `pending_players`.
- **Local**: an authenticated RPC that lets a human submit on behalf of a _bot
  seat in their own game_ (validate the caller is a participant and the target
  seat is a bot). The client computes the move with the same `BaseEngine`.

When implemented, the "your turn" notification trigger should skip bot seats
(bots have no `device_tokens`, so today it is a harmless no-op, but an explicit
guard documents intent).

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
