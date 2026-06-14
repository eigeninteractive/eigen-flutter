-- ============================================
-- Actions table (audit log - service role only)
-- ============================================

CREATE TABLE public.actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  bot_id  UUID REFERENCES public.bots(id),
  type action_type NOT NULL DEFAULT 'user',
  data JSONB NOT NULL,
  -- Denormalised from participants at write time so replay can attribute moves
  -- to a seat even after the account is deleted and user_id becomes NULL.
  player_index INT,
  -- The game_states.version produced by this action. Links each action
  -- to the resulting state snapshot for replay.
  version_after INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT actions_identity_check CHECK (
    -- user_id may be NULL for 'user' type if the account was later deleted
    (type = 'user'   AND bot_id IS NULL) OR
    (type = 'bot'    AND bot_id IS NOT NULL AND user_id IS NULL) OR
    -- system actions may carry the initiating player (forfeit) or no identity (timeout)
    (type = 'system' AND NOT (user_id IS NOT NULL AND bot_id IS NOT NULL))
  )
);

-- Index for replay ordering
CREATE INDEX idx_actions_game_timestamp ON public.actions(game_id, created_at);

-- RLS: Service role only (audit log)
ALTER TABLE public.actions ENABLE ROW LEVEL SECURITY;
-- No policies = deny all for authenticated users
