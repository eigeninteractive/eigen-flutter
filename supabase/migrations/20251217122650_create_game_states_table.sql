-- ============================================
-- Game states table (ground truth - service role only)
-- Append-only history: one row per (game_id, version).
-- Current state = ORDER BY version DESC LIMIT 1.
-- ============================================

CREATE TABLE public.game_states (
  game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  version INT NOT NULL,
  -- Pure game-specific payload (board, deck, fog map, ...). Must not carry
  -- whose-turn or winner info — those are first-class infra concerns on
  -- this row (pending_players, version) and on games (status).
  state JSONB NOT NULL,
  -- Player indices (0-based) allowed to submit an action right now.
  -- Sequential games: singleton; any-player games: every non-eliminated
  -- index; phased games: whatever the current phase permits. Empty array
  -- means no one may act (game over / aborted / paused).
  -- Stored here (not just in observations) so get_replay can call
  -- game_compute_observation without re-running game logic.
  pending_players INT[] NOT NULL,
  -- The game's base RNG seed: an opaque random string written once at start
  -- (v0) and copied verbatim onto every later row by the commit RPC. The EF
  -- derives each transition's generator from '<rng_seed>:<version>' (rand-seed
  -- sfc32 in _engine/observation.ts), so a replay re-derives every draw. Lives
  -- here rather than on games because this table is service-role-only — games
  -- rows are participant-readable, and a leaked seed would let a client
  -- predict every future shuffle.
  rng_seed TEXT NOT NULL,
  -- Absolute deadline for the current pending player(s) to act.
  -- NULL for untimed games. Set by infra after every action using
  -- games.turn_seconds or player bank time. Queried by submit_action
  -- (validation) and pg_cron (expire_turn enforcement).
  turn_deadline TIMESTAMPTZ,
  -- Remaining time budget per player in milliseconds (1-indexed array).
  -- NULL for games without an accumulated clock (budget_seconds IS NULL).
  -- Infra-owned: updated on every action. player_times[player_index + 1]
  -- is the budget for that player.
  player_times BIGINT[],
  -- Timestamp when the current turn began. Used to compute elapsed time
  -- for bank deduction on the next submit_action. NULL for untimed games.
  turn_started_at TIMESTAMPTZ,
  -- When this version was committed. Useful for audit and replay timeline.
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (game_id, version)
);

-- Index for fast current-state lookup (ORDER BY version DESC LIMIT 1)
-- and for expire_all_turns DISTINCT ON (game_id) ORDER BY version DESC.
CREATE INDEX idx_game_states_game_version
  ON public.game_states(game_id, version DESC);

-- Partial index used by expire_all_turns deadline filter (applied after
-- DISTINCT ON narrows to one row per game).
CREATE INDEX idx_game_states_turn_deadline
  ON public.game_states(turn_deadline)
  WHERE turn_deadline IS NOT NULL;

-- RLS: Service role only (no policies = deny all for authenticated users)
ALTER TABLE public.game_states ENABLE ROW LEVEL SECURITY;
