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
  -- Identity columns describe WHO performed the action and from which seat.
  -- A system action has no performer, so it carries no identity at all — the
  -- affected seat(s) live in the resulting state / game_outcomes, and the
  -- event_type (timeout / auto_forfeit) lives in `data`. A voluntary
  -- resign is a 'user' action (the user performed it); only the engine-driven
  -- account-deletion forfeit is a 'system' action.
  CONSTRAINT actions_identity_check CHECK (
    -- user_id may be NULL for 'user' type if the account was later deleted
    (type = 'user'   AND bot_id IS NULL) OR
    (type = 'bot'    AND bot_id IS NOT NULL AND user_id IS NULL) OR
    (type = 'system' AND user_id IS NULL AND bot_id IS NULL AND player_index IS NULL)
  ),
  -- version_after is the state version this action produced: a 1:1 link into
  -- game_states (the initial state, written by engine_commit_start, has no
  -- action). The FK enforces it and pins the state-before-action write order;
  -- the UNIQUE makes it a to-one so PostgREST can embed the action under its
  -- resulting state for replay.
  CONSTRAINT actions_state_fk FOREIGN KEY (game_id, version_after)
    REFERENCES public.game_states (game_id, version) ON DELETE CASCADE,
  CONSTRAINT actions_state_unique UNIQUE (game_id, version_after)
);

-- Index for replay ordering
CREATE INDEX idx_actions_game_timestamp ON public.actions(game_id, created_at);

-- RLS: Service role only (audit log)
ALTER TABLE public.actions ENABLE ROW LEVEL SECURITY;
-- No policies = deny all for authenticated users
