-- ============================================
-- Observations table (player-specific views)
-- ============================================

CREATE TABLE public.observations (
  game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- Player-specific projection of game_states.state.
  data JSONB NOT NULL,
  -- Mirror of game_states.pending_players. Denormalized onto every row so
  -- Realtime subscribers (which can only see observations, not game_states)
  -- can render turn info without a second subscription/JOIN. Clients derive
  -- "is my turn" locally as pending_players.contains(myPlayerIndex).
  pending_players INT[] NOT NULL,
  -- Mirror of game_states.version. Clients pass this back as the optimistic
  -- lock key on the next submit_action call.
  version INT NOT NULL DEFAULT 0,
  -- Mirror of game_states.turn_deadline. Null for untimed games.
  -- Clients use this to display countdown timers without a separate query.
  turn_deadline TIMESTAMPTZ,
  -- Mirror of game_states.player_times. Null for games without a bank.
  -- Clients use this to display per-player accumulated clock budgets.
  player_times BIGINT[],
  -- Mirror of game_states.turn_started_at. Null for untimed games.
  -- Clients combine with player_times to animate the active player's
  -- live countdown without polling.
  turn_started_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (game_id, user_id)
);

-- Index for realtime subscriptions
CREATE INDEX idx_observations_user_id ON public.observations(user_id);

-- Enable Realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE public.observations;

-- RLS: Users can only see their own observations
ALTER TABLE public.observations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "observations_select" ON public.observations 
  FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Updated_at trigger
CREATE TRIGGER update_observations_updated_at
  BEFORE UPDATE ON public.observations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

