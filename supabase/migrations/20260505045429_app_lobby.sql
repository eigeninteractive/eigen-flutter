-- ============================================
-- Client-direct lobby RPCs (PostgREST, RLS/auth)
-- ============================================
-- The app_* game RPCs the Dart client calls directly over PostgREST under
-- RLS/auth — joining, cancelling, leaving, discovery, and the local-bot view.
--
-- Naming: engine_* = service-role, EF-only gated RPCs (REVOKEd from
-- authenticated). cron_* = pg_cron-scheduled private jobs. app_* =
-- client-direct RPCs (PostgREST, under RLS/auth). do_*/other private.* =
-- internal helpers. See docs/engine_architecture.md.
-- ============================================

-- ============================================
-- RPC: app_join_game
-- Adds participant; transitions to 'ready' when player count is met.
-- ============================================
-- p_client_schema_version: the joining client's highest supported game schema
-- (GameModule.schemaVersion). Required, not defaulted: the server refuses to seat
-- a player in a game whose schema_version exceeds it, so a client never becomes a
-- participant in a game it cannot render. Omitting it fails function resolution
-- rather than silently skipping the gate — there is no caller that joins without a
-- known schema (every app build ships exactly one GameModule, and bots are seated
-- directly elsewhere, not via app_join_game). This is the only schema gate covering
-- all join paths (lobby, friends, by-code, deep link) atomically, since it runs
-- under the same FOR UPDATE lock as the seat INSERT.
CREATE OR REPLACE FUNCTION public.app_join_game(
  p_game_id               UUID,
  p_client_schema_version INT
)
RETURNS UUID AS $$
DECLARE
  v_participant_id    UUID;
  v_user_id           UUID;
  v_game_status       public.game_status;
  v_access            public.game_access;
  v_created_by        UUID;
  v_min_players       INT;
  v_max_players       INT;
  v_schema_version    INT;
  v_rated             BOOLEAN;
  v_participant_count INT;
BEGIN
  v_user_id := private.require_auth();

  -- Lock the game row to serialise concurrent join/leave/start operations.
  -- Without FOR UPDATE a concurrent engine_commit_start could commit (status='active')
  -- between this read and the participant INSERT, leaving a participant with
  -- no observation row.
  SELECT status, access, created_by, min_players, max_players, schema_version,
         rated
  INTO v_game_status, v_access, v_created_by, v_min_players, v_max_players,
       v_schema_version, v_rated
  FROM public.games WHERE id = p_game_id
  FOR UPDATE;

  IF v_game_status IS NULL THEN
    RAISE EXCEPTION 'Game not found' USING ERRCODE = 'EIG06';
  END IF;

  IF v_schema_version > p_client_schema_version THEN
    RAISE EXCEPTION 'Unsupported game schema: game requires schema %, client supports up to %',
      v_schema_version, p_client_schema_version
      USING ERRCODE = 'EIG12';
  END IF;

  IF v_game_status NOT IN ('waiting', 'ready') THEN
    RAISE EXCEPTION 'Game is not accepting players' USING ERRCODE = 'EIG10';
  END IF;

  -- Guests play unrated only — they cannot create rated games (see create_game)
  -- nor join one, which would create a player_ratings row and skew opponents'
  -- ratings against a throwaway account.
  IF v_rated AND private.is_anonymous() THEN
    RAISE EXCEPTION 'Rated games require a registered account';
  END IF;

  IF v_access = 'friends' AND v_user_id != v_created_by THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.relationships
      WHERE user_id_1 = LEAST(v_user_id, v_created_by)
        AND user_id_2 = GREATEST(v_user_id, v_created_by)
        AND status = 'accepted'
    ) THEN
      RAISE EXCEPTION 'Only friends of the creator can join this game'
        USING ERRCODE = 'EIG11';
    END IF;
  END IF;

  IF private.is_game_participant(p_game_id, v_user_id) THEN
    RAISE EXCEPTION 'Already joined this game' USING ERRCODE = 'EIG09';
  END IF;

  SELECT COUNT(*) INTO v_participant_count
  FROM public.participants WHERE game_id = p_game_id;

  IF v_participant_count >= v_max_players THEN
    RAISE EXCEPTION 'Game is full' USING ERRCODE = 'EIG08';
  END IF;

  INSERT INTO public.participants (game_id, user_id, player_index)
  VALUES (p_game_id, v_user_id, v_participant_count)
  RETURNING id INTO v_participant_id;

  IF v_participant_count + 1 >= v_min_players THEN
    UPDATE public.games SET status = 'ready' WHERE id = p_game_id;
  END IF;

  RETURN v_participant_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- ACCESS CONTROL
-- ============================================
-- Revoke from PUBLIC and anon, then re-grant to authenticated.
-- Revoking from PUBLIC covers the case where the default grant was to PUBLIC;
-- the explicit GRANT TO authenticated restores access for signed-in users.
-- ============================================

REVOKE EXECUTE ON FUNCTION public.app_join_game(uuid, integer) FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION public.app_join_game(uuid, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.app_cancel_game(p_game_id UUID)
RETURNS VOID AS $$
BEGIN
  PERFORM private.do_cancel_game(p_game_id, private.require_auth());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.app_cancel_game(uuid) FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION public.app_cancel_game(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.app_leave_game(p_game_id UUID)
RETURNS VOID AS $$
BEGIN
  PERFORM private.do_leave_game(p_game_id, private.require_auth());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.app_leave_game(uuid) FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION public.app_leave_game(uuid) TO authenticated;

-- (Server-bot HMAC verification + wake signing live in the edge function —
-- _engine/bot_auth.ts — keyed by HMAC(BOT_SIGNING_SECRET, bot_id); no per-bot
-- Vault secret or in-DB HMAC. The local-bot action route enforces this same gate
-- in TS against the roster it already reads; this SQL copy backs the direct-client
-- app_local_bot_observation RPC below, where the gate can only live in SQL.)

-- Reveals a local bot seat's LATEST observation to the SOLE human of a solo
-- game so the client can run the local bot (a bot acts on the current frame —
-- it has no use for history). Keyed by player_index (the client knows the
-- seat; allows duplicate local bots). The security gate lives in
-- private.resolve_local_bot_seat (caller is sole human; seat is a *local* bot) —
-- this is the only place the engine ever hands a bot's hidden view to a client.
-- Returns SETOF observations: the exact row shape a human reads from the table
-- directly, so the bot pull never drifts from the human pull.
CREATE OR REPLACE FUNCTION public.app_local_bot_observation(
  p_game_id      UUID,
  p_player_index INT
)
RETURNS SETOF public.observations
AS $$
BEGIN
  PERFORM private.resolve_local_bot_seat(
    p_game_id, p_player_index, private.require_auth()
  );

  RETURN QUERY
  SELECT o.*
  FROM public.observations o
  WHERE o.game_id = p_game_id AND o.player_index = p_player_index
  ORDER BY o.version DESC
  LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

-- app_local_bot_observation reads the stored observation row for the sole human
-- to drive a local bot client-side.
REVOKE EXECUTE ON FUNCTION public.app_local_bot_observation(UUID, INT) FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION public.app_local_bot_observation(UUID, INT) TO authenticated;

-- ============================================
-- Open-game lobby reads (shared projection + two access-scoped wrappers)
-- ============================================
-- Shared projection: one row per waiting/ready game NOT yet full, with its
-- participants embedded (so the client resolves identities via the cached
-- playerInfoProvider without extra queries) and a per-caller is_participant flag.
-- The full-game filter (participant count < max_players) is a HAVING on a JOIN
-- aggregate — PostgREST cannot express this as a WHERE on an embedded count, so
-- it lives here. auth.uid() resolves to the live caller inside the view.
--
-- This view carries NO access predicate (public vs friends) — that, plus cursor
-- pagination, lives in the app_lobby_games / app_friends_games wrappers below.
-- It MUST therefore stay in the `private` schema and stay ungranted: it is never
-- exposed via PostgREST, so a client cannot read it directly and bypass the
-- friends-visibility filter. The SECURITY DEFINER wrappers (owner = postgres)
-- read it as owner; default view security (security_invoker = false) keeps that
-- behaviour, matching how these reads have always bypassed base-table RLS and
-- scoped visibility through the wrapper's WHERE instead.
CREATE OR REPLACE VIEW private.open_games_with_participants AS
  SELECT
    g.id,
    g.created_by,
    g.status,
    g.access,
    g.turn_seconds,
    g.budget_seconds,
    g.increment_seconds,
    g.min_players,
    g.max_players,
    g.config,
    g.schema_version,
    g.rated,
    g.rating_pool,
    g.created_at,
    g.finished_at,
    g.updated_at,
    COALESCE(
      jsonb_agg(
        to_jsonb(p)
      ) FILTER (WHERE p.id IS NOT NULL),
      '[]'::jsonb
    ) AS participants,
    EXISTS (
      SELECT 1 FROM public.participants pp
      WHERE pp.game_id = g.id AND pp.user_id = auth.uid()
    ) AS is_participant
  FROM public.games g
  LEFT JOIN public.participants p ON p.game_id = g.id
  WHERE g.status IN ('waiting', 'ready')
  GROUP BY g.id
  HAVING COUNT(p.id) < g.max_players;

-- RPC: app_lobby_games — public games open for joining, newest first (cursor
-- pagination on created_at). Thin access-scoped wrapper over the shared view.
CREATE OR REPLACE FUNCTION public.app_lobby_games(
  p_cursor TIMESTAMPTZ DEFAULT NULL,
  p_limit  INT         DEFAULT 50
)
RETURNS SETOF private.open_games_with_participants AS $$
  SELECT *
  FROM private.open_games_with_participants v
  WHERE v.access = 'public'
    AND (p_cursor IS NULL OR v.created_at < p_cursor)
  ORDER BY v.created_at DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.app_lobby_games(timestamptz, integer) FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION public.app_lobby_games(timestamptz, integer) TO authenticated;

-- ============================================
-- Game joining / discovery extensions
-- ============================================

CREATE OR REPLACE FUNCTION public.app_join_game_by_code(
  p_code                  VARCHAR,
  p_client_schema_version INT
)
RETURNS UUID AS $$
DECLARE
  v_game_id UUID;
BEGIN
  PERFORM private.require_auth();
  SELECT id INTO v_game_id FROM public.games WHERE short_code = upper(p_code);
  IF v_game_id IS NULL THEN
    RAISE EXCEPTION 'Game not found' USING ERRCODE = 'EIG06';
  END IF;

  -- Delegate to standard app_join_game, forwarding the schema gate so a by-code or
  -- deep-link join is rejected before seating just like a lobby join.
  RETURN public.app_join_game(v_game_id, p_client_schema_version);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.app_join_game_by_code(varchar, integer) FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION public.app_join_game_by_code(varchar, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.app_friends_games(
  p_cursor TIMESTAMPTZ DEFAULT NULL,
  p_limit  INT         DEFAULT 50
)
RETURNS SETOF private.open_games_with_participants AS $$
  -- Thin access-scoped wrapper over the shared view. Returns friends-access
  -- rooms the caller may see: their own (you are not "friends with yourself",
  -- so the relationship check alone would hide a creator's own rooms) or those
  -- created by an accepted friend.
  SELECT *
  FROM private.open_games_with_participants v
  WHERE v.access = 'friends'
    AND (p_cursor IS NULL OR v.created_at < p_cursor)
    AND (
      v.created_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.relationships r
        WHERE ((r.user_id_1 = v.created_by AND r.user_id_2 = auth.uid())
           OR (r.user_id_2 = v.created_by AND r.user_id_1 = auth.uid()))
          AND r.status = 'accepted'
      )
    )
  ORDER BY v.created_at DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.app_friends_games(timestamptz, integer) FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION public.app_friends_games(timestamptz, integer) TO authenticated;
