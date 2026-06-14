-- ============================================
-- Player Ratings table
-- ============================================
-- Per-player per-pool OpenSkill (Bayesian) rating.
-- One row per (player, pool) pair — upserted after each rated game.
-- Both user_id and bot_id are nullable; exactly one must be set (XOR).
CREATE TABLE public.player_ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  bot_id  UUID REFERENCES public.bots(id)  ON DELETE CASCADE,
  pool TEXT NOT NULL,
  -- OpenSkill Gaussian parameters.
  mu    DOUBLE PRECISION NOT NULL DEFAULT 25.0,
  sigma DOUBLE PRECISION NOT NULL DEFAULT 25.0 / 3.0,
  -- display_rating = max(0, round((mu - 3 * sigma) * 40))
  -- Kept denormalised for cheap leaderboard and view queries.
  display_rating INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT player_rating_xor CHECK ((user_id IS NULL) != (bot_id IS NULL))
);

-- One rating per human player per pool.
CREATE UNIQUE INDEX idx_player_ratings_user_pool
  ON public.player_ratings(user_id, pool)
  WHERE user_id IS NOT NULL;

-- One rating per bot per pool.
CREATE UNIQUE INDEX idx_player_ratings_bot_pool
  ON public.player_ratings(bot_id, pool)
  WHERE bot_id IS NOT NULL;

-- Trigger to auto-update updated_at.
CREATE TRIGGER update_player_ratings_updated_at
  BEFORE UPDATE ON public.player_ratings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- RLS: any authenticated user can read ratings (leaderboards, profiles).
ALTER TABLE public.player_ratings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "player_ratings_select" ON public.player_ratings
  FOR SELECT TO authenticated USING (true);

-- ============================================
-- Rating History table
-- ============================================
-- One row per player per rated game — immutable audit log.
CREATE TABLE public.rating_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  bot_id  UUID REFERENCES public.bots(id)  ON DELETE CASCADE,
  game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  pool TEXT NOT NULL,
  -- Snapshot before this game.
  mu_before      DOUBLE PRECISION NOT NULL,
  sigma_before   DOUBLE PRECISION NOT NULL,
  display_before INT NOT NULL,
  -- Snapshot after this game.
  mu_after      DOUBLE PRECISION NOT NULL,
  sigma_after   DOUBLE PRECISION NOT NULL,
  display_after INT NOT NULL,
  -- Signed delta for quick display (positive = gained, negative = lost).
  display_change INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT rating_history_xor CHECK ((user_id IS NULL) != (bot_id IS NULL))
);

CREATE INDEX idx_rating_history_user_pool
  ON public.rating_history(user_id, pool, created_at DESC)
  WHERE user_id IS NOT NULL;
CREATE INDEX idx_rating_history_game
  ON public.rating_history(game_id);

-- One rating-history row per player per game — enforced at the DB level so a
-- duplicate edge-function call cannot insert a second row.
CREATE UNIQUE INDEX idx_rating_history_game_user
  ON public.rating_history(game_id, user_id)
  WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX idx_rating_history_game_bot
  ON public.rating_history(game_id, bot_id)
  WHERE bot_id IS NOT NULL;

-- RLS: users can only read their own rating history.
ALTER TABLE public.rating_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rating_history_select" ON public.rating_history
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- pg_net is required for net.http_post used in the trigger below.
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ============================================
-- pg_net trigger: fire Edge Function on rated game finish
-- ============================================
-- Reads URL from private.app_config and secret from Vault.
-- Fires only when a rated game transitions to 'finished' for the first time.
--
-- The payload is self-contained: outcomes + current ratings are bundled so
-- the edge function is a pure computation service — no DB schema knowledge
-- needed for the rating logic itself.
CREATE OR REPLACE FUNCTION private.notify_rating_update()
RETURNS TRIGGER AS $$
DECLARE
  v_base_url TEXT;
  v_secret   TEXT;
  v_players  JSONB;
BEGIN
  IF NEW.status != 'finished'
     OR OLD.status = 'finished'
     OR NOT NEW.rated THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_base_url
    FROM private.app_config WHERE key = 'serverless_base_url';
  SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets WHERE name = 'serverless_secret';

  IF v_base_url IS NULL OR v_base_url = '' THEN
    RAISE WARNING 'Rating update skipped for game %: serverless_base_url not configured', NEW.id;
    RETURN NEW;
  END IF;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'Rating update skipped for game %: serverless_secret not in Vault', NEW.id;
    RETURN NEW;
  END IF;

  -- Bundle outcomes + current ratings for each player.
  -- finish_game inserts game_outcomes before updating games.status, so
  -- these rows are guaranteed to exist by the time this trigger fires.
  -- player_ratings uses LEFT JOIN — defaults (25, 25/3) applied here
  -- so the edge function never needs to know about the DB schema.
  SELECT jsonb_agg(jsonb_build_object(
    'player_index',   go.player_index,
    'user_id',        go.user_id,
    'bot_id',         go.bot_id,
    'placement',      go.placement,
    'team_index',     go.team_index,
    'mu',             COALESCE(pr.mu,             25.0),
    'sigma',          COALESCE(pr.sigma,           25.0 / 3.0),
    'display_rating', COALESCE(pr.display_rating,  0)
  ) ORDER BY go.player_index)
  INTO v_players
  FROM public.game_outcomes go
  LEFT JOIN public.player_ratings pr
    ON  pr.pool = NEW.rating_pool
    AND (
      (go.user_id IS NOT NULL AND pr.user_id = go.user_id)
      OR
      (go.bot_id  IS NOT NULL AND pr.bot_id  = go.bot_id)
    )
  WHERE go.game_id = NEW.id;

  PERFORM net.http_post(
    url     := v_base_url || '/update-ratings',
    headers := jsonb_build_object(
      'Content-Type',     'application/json',
      'x-webhook-secret', v_secret
    ),
    body    := jsonb_build_object(
      'game_id',     NEW.id,
      'rating_pool', NEW.rating_pool,
      'players',     COALESCE(v_players, '[]'::jsonb)
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE TRIGGER on_game_finished_update_ratings
  AFTER UPDATE ON public.games
  FOR EACH ROW EXECUTE FUNCTION private.notify_rating_update();

-- ============================================
-- RPC: apply_rating_updates
-- Applies pre-computed OpenSkill updates for one rated game.
-- Called by the update-ratings edge function, which owns the computation.
-- Separating writes here keeps the edge function fully schema-unaware.
-- ============================================
CREATE OR REPLACE FUNCTION public.apply_rating_updates(
  p_game_id UUID,
  p_pool    TEXT,
  p_updates JSONB
)
RETURNS VOID AS $$
DECLARE
  v_user_id    UUID;
  v_bot_id     UUID;
  v_mu_before  DOUBLE PRECISION;
  v_sig_before DOUBLE PRECISION;
  v_dis_before INT;
  v_mu_after   DOUBLE PRECISION;
  v_sig_after  DOUBLE PRECISION;
  v_dis_after  INT;
BEGIN
  FOR v_user_id, v_bot_id,
      v_mu_before, v_sig_before, v_dis_before,
      v_mu_after,  v_sig_after,  v_dis_after
  IN
    SELECT
      (elem->'identity'->>'user_id')::UUID,
      (elem->'identity'->>'bot_id')::UUID,
      (elem->'before'->>'mu')::DOUBLE PRECISION,
      (elem->'before'->>'sigma')::DOUBLE PRECISION,
      (elem->'before'->>'display_rating')::INT,
      (elem->'after'->>'mu')::DOUBLE PRECISION,
      (elem->'after'->>'sigma')::DOUBLE PRECISION,
      (elem->'after'->>'display_rating')::INT
    FROM jsonb_array_elements(p_updates) AS elem
  LOOP
    -- Skip players whose account was deleted between game finish and this call.
    -- The other players in the game still receive their rating updates.
    IF v_user_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.users WHERE id = v_user_id
    ) THEN
      CONTINUE;
    END IF;

    IF v_user_id IS NOT NULL THEN
      INSERT INTO public.player_ratings (user_id, pool, mu, sigma, display_rating)
      VALUES (v_user_id, p_pool, v_mu_after, v_sig_after, v_dis_after)
      ON CONFLICT (user_id, pool) WHERE user_id IS NOT NULL
        DO UPDATE SET mu = EXCLUDED.mu, sigma = EXCLUDED.sigma,
                      display_rating = EXCLUDED.display_rating;
    ELSE
      INSERT INTO public.player_ratings (bot_id, pool, mu, sigma, display_rating)
      VALUES (v_bot_id, p_pool, v_mu_after, v_sig_after, v_dis_after)
      ON CONFLICT (bot_id, pool) WHERE bot_id IS NOT NULL
        DO UPDATE SET mu = EXCLUDED.mu, sigma = EXCLUDED.sigma,
                      display_rating = EXCLUDED.display_rating;
    END IF;

    INSERT INTO public.rating_history
      (user_id, bot_id, game_id, pool,
       mu_before, sigma_before, display_before,
       mu_after,  sigma_after,  display_after, display_change)
    VALUES
      (v_user_id, v_bot_id, p_game_id, p_pool,
       v_mu_before, v_sig_before, v_dis_before,
       v_mu_after,  v_sig_after,  v_dis_after,
       v_dis_after - v_dis_before);
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Only the service_role (used by the edge function) may call this.
-- anon and authenticated roles must not be able to forge rating writes.
REVOKE EXECUTE ON FUNCTION public.apply_rating_updates(UUID, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
