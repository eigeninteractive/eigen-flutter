-- ============================================
-- Observations table (player-specific views)
-- ============================================
-- Append-only history: one row per (game_id, player_index, version), mirroring
-- game_states' one-row-per-version model. The latest frame for a seat =
-- ORDER BY version DESC LIMIT 1. Rows are immutable once written.
--
-- Append-only (rather than upsert-latest) is what makes the client's frame
-- stream *reliable*: Realtime can drop messages, but a client that sees a
-- version gap can SELECT the missing rows and animate through them in order —
-- with upsert the intermediate frames would be gone. It also makes the live
-- stream and a replay the same shape: an ordered per-seat frame sequence.

CREATE TABLE public.observations (
  game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  -- Exactly one of user_id / bot_id is set (XOR below): rows exist per
  -- participant, human or bot. Bot rows (user_id NULL) are invisible to the
  -- authenticated SELECT policy, so humans/Realtime never see them — a feature.
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  bot_id  UUID REFERENCES public.bots(id)  ON DELETE CASCADE,
  -- Seat index this row belongs to. Part of the primary key so the fan-out can
  -- insert by seat regardless of human/bot identity.
  player_index INT NOT NULL,
  -- Mirror of game_states.version: the state version this frame projects.
  -- Clients pass the latest version back as the optimistic lock key on the
  -- next submit_action call, and use gaps in it to fetch missed frames.
  version INT NOT NULL,
  -- Player-specific projection of game_states.state at this version. May embed
  -- per-seat transition cues (e.g. a lastMove field) — computeObservation
  -- receives the transition's cause exactly so games can do this.
  data JSONB NOT NULL,
  -- This seat's VIEW of game_states.pending_players, projected per seat by
  -- computeObservation — hidden-info games may narrow it (e.g. not revealing
  -- who can act in a reaction window). Denormalized onto every row so Realtime
  -- subscribers (which can only see observations, not game_states) can render
  -- turn info without a second subscription/JOIN. Clients derive "is my turn"
  -- locally as pending_players.contains(myPlayerIndex), so a game must never
  -- narrow a seat's own membership out of that seat's row.
  pending_players INT[] NOT NULL,
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
  -- Human XOR bot, mirroring participants/actions/outcomes identity rule.
  CONSTRAINT observation_identity_xor CHECK ((user_id IS NULL) != (bot_id IS NULL)),
  -- The PK index also serves the latest-frame lookup (backward scan on the
  -- (game_id, player_index) prefix) and the gap-recovery range fetch.
  PRIMARY KEY (game_id, player_index, version)
);

-- Index for RLS-augmented queries on human rows (user_id = auth.uid()).
CREATE INDEX idx_observations_user_id ON public.observations(user_id)
  WHERE user_id IS NOT NULL;

-- Broadcast-from-database fan-out: each human seat's frame is sent to that
-- seat's private topic `game:{game_id}:user:{user_id}` via realtime.send.
-- The trigger's WHEN clause is the guarantee that bot rows never broadcast.
-- A trigger (rather than sends inlined in the commit functions) covers both
-- insert choke points — engine_commit_start's version-0 fan-out and
-- write_observation_slices — and any future insert path.
CREATE OR REPLACE FUNCTION private.broadcast_observation()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM realtime.send(
    to_jsonb(NEW),
    'observation',
    'game:' || NEW.game_id || ':user:' || NEW.user_id,
    true
  );
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE TRIGGER broadcast_observation_insert
  AFTER INSERT ON public.observations
  FOR EACH ROW
  WHEN (NEW.user_id IS NOT NULL)
  EXECUTE FUNCTION private.broadcast_observation();

-- Private-channel authorization: a user may join only their own seat topics
-- (any topic ending in `:user:{auth.uid()}`). No participant check is needed:
-- only rows with user_id = auth.uid() are ever sent to such a topic, and
-- clients cannot publish on private channels (no INSERT policy on
-- realtime.messages), so joining a foreign game's own-seat topic yields
-- nothing.
CREATE POLICY "observations_broadcast_read" ON realtime.messages
  FOR SELECT
  TO authenticated
  USING (
    extension = 'broadcast'
    AND split_part(realtime.topic(), ':user:', 2) = (SELECT auth.uid()::text)
  );

-- RLS: Users can only see their own observations
ALTER TABLE public.observations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "observations_select" ON public.observations
  FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));
