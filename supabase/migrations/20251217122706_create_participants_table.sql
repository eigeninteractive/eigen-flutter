-- ============================================
-- Participants table
-- ============================================

CREATE TABLE public.participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  -- Set for bot participants; NULL for humans.
  -- Both may be NULL when a human account is deleted — mid-game (the purge's
  -- forfeit may leave a multiplayer game active) or after it finishes.
  bot_id UUID REFERENCES public.bots(id),
  player_index INT NOT NULL,
  type participant_type NOT NULL DEFAULT 'human',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT participant_identity CHECK (
    NOT (user_id IS NOT NULL AND bot_id IS NOT NULL)
  )
);

-- Unique constraint: one participant per user per game (bots excluded)
CREATE UNIQUE INDEX idx_participants_unique
  ON public.participants(game_id, user_id)
  WHERE user_id IS NOT NULL;

-- Unique constraint: one participant per seat per game (covers race condition in app_join_game)
CREATE UNIQUE INDEX idx_participants_player_index
  ON public.participants(game_id, player_index);

-- Indices
CREATE INDEX idx_participants_user_id ON public.participants(user_id);
CREATE INDEX idx_participants_game_id ON public.participants(game_id);

-- ============================================
-- Helper function for RLS (must be after participants table exists)
-- ============================================
CREATE OR REPLACE FUNCTION private.is_game_participant(p_game_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.participants 
    WHERE game_id = p_game_id AND user_id = p_user_id
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = '';

-- ============================================
-- Games RLS policy (deferred from games migration)
-- ============================================
CREATE POLICY "games_select" ON public.games
  FOR SELECT
  TO authenticated
  USING (
    access = 'public'
    OR created_by = (SELECT auth.uid())
    OR private.is_game_participant(id, (SELECT auth.uid()))
  );

-- ============================================
-- Participants RLS
-- ============================================
ALTER TABLE public.participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "participants_select" ON public.participants
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.games g
      WHERE g.id = game_id AND (
        g.access = 'public'
        OR g.created_by = (SELECT auth.uid())
        OR private.is_game_participant(g.id, (SELECT auth.uid()))
      )
    )
  );
