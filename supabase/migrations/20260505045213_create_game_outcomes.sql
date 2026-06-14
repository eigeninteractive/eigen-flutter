-- ============================================
-- game_outcomes table
-- One row per participant per completed game.
-- Supports multi-winner (team games), score-based ELO, placement-based ELO,
-- and mid-game elimination.
-- ============================================
CREATE TABLE public.game_outcomes (
  game_id      UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  player_index INT  NOT NULL,
  -- null for bot participants; SET NULL when the account is deleted so the
  -- outcome row (player_index, result, placement) is preserved for analysis.
  user_id      UUID REFERENCES public.users(id) ON DELETE SET NULL,
  bot_id       UUID REFERENCES public.bots(id),   -- null for human participants
  result       game_result NOT NULL,
  score        NUMERIC,   -- optional raw game score (e.g. chips, books captured)
  placement    INT NOT NULL, -- ordinal finish rank (1 = best); used directly for rating
  team_index   INT NOT NULL, -- players sharing a team_index are rated as one team
  PRIMARY KEY (game_id, player_index),
  -- Both may be NULL when the human player's account was deleted after the game.
  CONSTRAINT game_outcome_identity CHECK (
    NOT (user_id IS NOT NULL AND bot_id IS NOT NULL)
  )
);

CREATE INDEX idx_game_outcomes_game_id ON public.game_outcomes(game_id);
CREATE INDEX idx_game_outcomes_user_id ON public.game_outcomes(user_id)
  WHERE user_id IS NOT NULL;

ALTER TABLE public.game_outcomes ENABLE ROW LEVEL SECURITY;

-- Public games: anyone can read. Private/friends games: only participants or creator.
CREATE POLICY "game_outcomes_select" ON public.game_outcomes
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.games g
      WHERE g.id = game_id
        AND (
          g.access = 'public'
          OR g.created_by = (SELECT auth.uid())
          OR EXISTS (
            SELECT 1 FROM public.participants p
            WHERE p.game_id = game_id
              AND p.user_id = (SELECT auth.uid())
          )
        )
    )
  );
