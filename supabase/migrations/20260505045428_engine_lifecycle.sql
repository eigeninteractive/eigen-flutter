-- ============================================
-- Account teardown & pg_cron sweeps
-- ============================================
-- engine_purge_user (the shared teardown) plus the scheduled cron_* jobs. The
-- cron entry points are scheduled in the cron_jobs migration.
--
-- Naming: engine_* = service-role, EF-only gated RPCs (REVOKEd from
-- authenticated). cron_* = pg_cron-scheduled private jobs. app_* =
-- client-direct RPCs (PostgREST, under RLS/auth). do_*/other private.* =
-- internal helpers. See docs/engine_architecture.md.
-- ============================================

-- Pure-SQL account teardown: cancel created lobbies, leave joined lobbies, then
-- delete the auth user. The active-game forfeits are done by the EF first (they
-- need the TS rules), so this does not forfeit.
CREATE OR REPLACE FUNCTION public.engine_purge_user(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_game RECORD;
BEGIN
  FOR v_game IN
    SELECT id FROM public.games
    WHERE created_by = p_user_id AND status IN ('waiting', 'ready')
    FOR UPDATE
  LOOP
    PERFORM private.do_cancel_game(v_game.id, p_user_id);
  END LOOP;

  FOR v_game IN
    SELECT g.id FROM public.games g
    JOIN public.participants p ON p.game_id = g.id AND p.user_id = p_user_id
    WHERE g.status IN ('waiting', 'ready') AND g.created_by != p_user_id
    FOR UPDATE OF g
  LOOP
    PERFORM private.do_leave_game(v_game.id, p_user_id);
  END LOOP;

  DELETE FROM auth.users WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.engine_purge_user(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.engine_purge_user(UUID) TO service_role;

-- The two sweeps below use net.http_post (pg_net, created in the foundation
-- migration) to hop to the `internal` edge function (timeout expiry, stale-guest
-- cleanup).

-- pg_cron sweep: collect every game whose deadline + grace has passed and wake
-- the EF /internal/expire route ONCE per tick with the whole batch (fire-and-
-- forget via pg_net). The timeout *consequence* runs in the TS rules. The tick
-- (a cheap indexed query) lives in the DB; the EF is woken only when there is
-- work — an idle deployment makes zero http_post calls. A LIMIT caps each batch
-- so one EF invocation stays bounded under a spike; the next tick catches the
-- rest (the sweep is self-healing — it re-selects any game still expired). URL
-- from app_config, secret from Vault — the same convention as the FCM webhooks.
CREATE OR REPLACE FUNCTION private.cron_expire_turns()
RETURNS VOID AS $$
DECLARE
  v_base_url  TEXT;
  v_secret    TEXT;
  v_game_ids  UUID[];
BEGIN
  SELECT value INTO v_base_url FROM private.app_config WHERE key = 'serverless_base_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'secret_api_key';
  IF v_base_url IS NULL OR v_base_url = '' THEN
    RAISE WARNING 'expire sweep skipped: serverless_base_url not configured';
    RETURN;
  END IF;
  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'expire sweep skipped: secret_api_key not in Vault';
    RETURN;
  END IF;

  SELECT array_agg(latest.game_id)
  INTO v_game_ids
  FROM (
    SELECT latest.game_id
    FROM (
      SELECT DISTINCT ON (gs.game_id) gs.game_id, gs.turn_deadline
      FROM   public.game_states gs
      JOIN   public.games g ON g.id = gs.game_id
      WHERE  g.status = 'active'
      ORDER  BY gs.game_id, gs.version DESC
    ) latest
    WHERE private.deadline_expired(latest.turn_deadline, NOW())
    LIMIT 200
  ) latest;

  IF v_game_ids IS NULL OR array_length(v_game_ids, 1) = 0 THEN
    RETURN;
  END IF;

  -- The engine EF's /engine/internal/* group runs @supabase/server's
  -- `auth: 'secret'` mode: it validates this apikey header against the
  -- project's secret API key (the same key the platform injects into the
  -- function), so no bespoke webhook secret exists.
  PERFORM net.http_post(
    url     := v_base_url || '/engine/internal/expire',
    headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_secret),
    body    := jsonb_build_object('game_ids', to_jsonb(v_game_ids))
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Active game ids a user holds a seat in. Internal helper for the stale-guest
-- sweep below (which runs in SQL); the EF reads the same fact directly via the
-- SDK on the account-deletion path.
CREATE OR REPLACE FUNCTION private.user_active_game_ids(p_user_id UUID)
RETURNS UUID[] AS $$
  SELECT COALESCE(array_agg(g.id), '{}')
  FROM public.games g
  JOIN public.participants p ON p.game_id = g.id AND p.user_id = p_user_id
  WHERE g.status = 'active';
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '';

-- pg_cron sweep: clean up stale anonymous (guest) accounts. The work splits by
-- whether the guest still holds active games:
--   * none  → no game rules needed, so purge right here in SQL (no EF hop).
--   * some  → a forfeit's consequence is game-defined (a multiplayer forfeit may
--             leave the game active), so the seats must be forfeited via the TS
--             rules before purging. Those guests are batched to the EF
--             /internal/purge-users route in ONE hop; the EF forfeits-then-purges.
-- The EF is woken only when at least one guest needs the rules.
CREATE OR REPLACE FUNCTION private.cron_cleanup_stale_guests()
RETURNS VOID AS $$
DECLARE
  v_base_url    TEXT;
  v_secret      TEXT;
  v_user_id     UUID;
  v_active_ids  UUID[];
  v_with_active UUID[] := '{}';
BEGIN
  SELECT value INTO v_base_url FROM private.app_config WHERE key = 'serverless_base_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'secret_api_key';

  -- Stale guests: anonymous accounts older than 7 days with no action in the
  -- last 2 days. Those with no active games are purged here in SQL; the rest are
  -- batched to the EF below to forfeit (via the rules) then purge.
  FOR v_user_id IN
    SELECT au.id
    FROM auth.users au
    WHERE au.is_anonymous = true
      AND au.created_at < NOW() - INTERVAL '7 days'
      AND NOT EXISTS (
        SELECT 1 FROM public.actions a
        WHERE a.user_id = au.id AND a.created_at >= NOW() - INTERVAL '2 days'
      )
  LOOP
    v_active_ids := private.user_active_game_ids(v_user_id);
    IF array_length(v_active_ids, 1) IS NULL THEN
      PERFORM public.engine_purge_user(v_user_id);
    ELSE
      v_with_active := array_append(v_with_active, v_user_id);
    END IF;
  END LOOP;

  IF array_length(v_with_active, 1) IS NULL THEN
    RETURN;  -- every stale guest was purged in SQL; nothing needs the rules
  END IF;

  IF v_base_url IS NULL OR v_base_url = '' THEN
    RAISE WARNING 'stale-guest cleanup: % guest(s) need forfeit but serverless_base_url not configured',
      array_length(v_with_active, 1);
    RETURN;
  END IF;
  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'stale-guest cleanup: % guest(s) need forfeit but secret_api_key not in Vault',
      array_length(v_with_active, 1);
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := v_base_url || '/engine/internal/purge-users',
    headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_secret),
    body    := jsonb_build_object('user_ids', to_jsonb(v_with_active))
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- CRON: cron_cleanup_idle_games
-- Called by pg_cron daily. Silently aborts abandoned games:
--   - waiting or ready games idle for > 7 days
--   - active untimed games with no action in the last 30 days
-- Timed games don't need this — clock expiry handles them via cron_expire_turns.
-- No hook call, no outcomes written — just a status transition to 'aborted'.
-- ============================================
CREATE OR REPLACE FUNCTION private.cron_cleanup_idle_games()
RETURNS VOID AS $$
BEGIN
  -- Abort waiting/ready games not touched in 7 days.
  UPDATE public.games
  SET status = 'aborted', finished_at = NOW()
  WHERE status IN ('waiting', 'ready')
    AND updated_at < NOW() - INTERVAL '7 days';

  -- Abort untimed active games with no action in 30 days.
  -- turn_seconds IS NULL AND budget_seconds IS NULL → untimed game.
  UPDATE public.games g
  SET status = 'aborted', finished_at = NOW()
  WHERE g.status = 'active'
    AND g.turn_seconds IS NULL
    AND g.budget_seconds IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.actions a
      WHERE a.game_id = g.id
        AND a.created_at >= NOW() - INTERVAL '30 days'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';
