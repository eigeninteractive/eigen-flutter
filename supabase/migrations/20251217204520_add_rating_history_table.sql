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
  -- Kept denormalised for cheap leaderboard and view queries. Derived in SQL by
  -- private.apply_rating_updates (the single source of the formula).
  display_rating INT NOT NULL DEFAULT 0,
  -- Optimistic-concurrency token bumped on every rating write. The edge function
  -- reads it with the (mu, sigma) baseline and the commit applies the new rating
  -- only if it is unchanged (compare-and-swap in apply_rating_updates), so two
  -- games finishing for the same identity across different game locks cannot lose
  -- an update. No default: apply_rating_updates is the only writer and always sets
  -- it explicitly (1 on a first-time row, revision + 1 on update), so an implicit
  -- value would only ever mask a bug. 0 is the EF's "no row yet" sentinel and is
  -- never a stored value.
  revision INTEGER NOT NULL,
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

-- ============================================
-- private.apply_rating_updates — writes EF-computed OpenSkill ratings (CAS)
-- ============================================
-- Game Engine + OpenSkill run in the `game` edge function: on a rated finish the
-- EF computes each identity's new (mu, sigma) and the gated commit RPC calls this
-- writer in the SAME transaction as the game finish (see
-- private.persist_transition). Lives in the `private` schema (engine-internal);
-- the EF never calls it directly.
--
-- Optimistic concurrency: player_ratings is shared across games, and the games
-- lock only serialises writers within one game. The EF reads each identity's
-- `revision` with the baseline and passes it back as `expected_revision`; here we
-- apply the new rating only if the row's revision is still that value, bumping it.
-- A mismatch means a concurrent finish for the same identity moved the rating, so
-- we RAISE (SQLSTATE EIG01) to roll the whole finish back; the EF re-reads the
-- fresh baseline, recomputes, and retries. A revision match proves the current row
-- IS the baseline this (mu, sigma) was computed from, so `before` and the display
-- number are derived here rather than sent — the display formula lives only here.
CREATE OR REPLACE FUNCTION private.apply_rating_updates(
  p_game_id UUID,
  p_pool    TEXT,
  p_updates JSONB
)
RETURNS VOID AS $$
DECLARE
  v_user_id      UUID;
  v_bot_id       UUID;
  v_mu_after     DOUBLE PRECISION;
  v_sig_after    DOUBLE PRECISION;
  v_expected_rev INT;
  v_mu_before    DOUBLE PRECISION;
  v_sig_before   DOUBLE PRECISION;
  v_dis_before   INT;
  v_dis_after    INT;
  v_cur_rev      INT;
BEGIN
  -- Canonical identity order so two finishing transactions that share identities
  -- lock the player_ratings rows in the same order — no cross-game deadlock.
  FOR v_user_id, v_bot_id, v_mu_after, v_sig_after, v_expected_rev IN
    SELECT
      (elem->'identity'->>'user_id')::UUID,
      (elem->'identity'->>'bot_id')::UUID,
      (elem->>'mu')::DOUBLE PRECISION,
      (elem->>'sigma')::DOUBLE PRECISION,
      (elem->>'expected_revision')::INT
    FROM jsonb_array_elements(p_updates) AS elem
    ORDER BY COALESCE(elem->'identity'->>'user_id', elem->'identity'->>'bot_id')
  LOOP
    -- Skip players whose account was deleted between game finish and this call.
    -- The other players in the game still receive their rating updates.
    IF v_user_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.users WHERE id = v_user_id
    ) THEN
      CONTINUE;
    END IF;

    -- Derived display number — single source of the formula.
    v_dis_after := GREATEST(0, round((v_mu_after - 3 * v_sig_after) * 40))::INT;

    -- Capture the prior snapshot + its revision, locking the row if it exists.
    SELECT mu, sigma, display_rating, revision
    INTO v_mu_before, v_sig_before, v_dis_before, v_cur_rev
    FROM public.player_ratings
    WHERE (user_id = v_user_id OR bot_id = v_bot_id) AND pool = p_pool
    FOR UPDATE;

    IF FOUND THEN
      -- We hold the row lock, so a single compare-and-swap against the baseline the
      -- EF read settles it; the plain UPDATE below cannot then lose a race.
      IF v_cur_rev <> v_expected_rev THEN
        RAISE EXCEPTION 'Rating baseline moved for game % identity %',
          p_game_id, COALESCE(v_user_id::TEXT, v_bot_id::TEXT)
          USING ERRCODE = 'EIG01';
      END IF;
      UPDATE public.player_ratings
         SET mu = v_mu_after, sigma = v_sig_after,
             display_rating = v_dis_after, revision = revision + 1
       WHERE (user_id = v_user_id OR bot_id = v_bot_id) AND pool = p_pool;
    ELSE
      -- Never-rated identity: the EF computed `after` from the OpenSkill defaults,
      -- so `before` is those defaults and the expected revision must be the 0
      -- sentinel (a non-zero one means the row it read has since vanished — stale).
      IF v_expected_rev <> 0 THEN
        RAISE EXCEPTION 'Rating baseline moved for game % identity %',
          p_game_id, COALESCE(v_user_id::TEXT, v_bot_id::TEXT)
          USING ERRCODE = 'EIG01';
      END IF;
      v_mu_before  := 25.0;
      v_sig_before := 25.0 / 3.0;
      v_dis_before := 0;
      -- FOR UPDATE locked nothing (no row), so a concurrent finish can insert this
      -- identity first; the unique index turns that race into a unique_violation,
      -- which is the same lost-baseline conflict.
      BEGIN
        INSERT INTO public.player_ratings
          (user_id, bot_id, pool, mu, sigma, display_rating, revision)
        VALUES (v_user_id, v_bot_id, p_pool, v_mu_after, v_sig_after, v_dis_after, 1);
      EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'Rating baseline moved for game % identity %',
          p_game_id, COALESCE(v_user_id::TEXT, v_bot_id::TEXT)
          USING ERRCODE = 'EIG01';
      END;
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
