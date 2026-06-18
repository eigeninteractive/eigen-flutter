# Future Plans

Designs for features that are **not yet built**. `engine_architecture.md` and
`game_implementation_guide.md` describe the system as it exists today; anything
speculative lives here until it ships, then moves into those docs.

Each entry is a self-contained slice intended to land as its own PR.

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
