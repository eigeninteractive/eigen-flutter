-- ============================================
-- Engine game creation & bot seating (service-role, EF-only)
-- ============================================
-- Thin atomic writers behind the /game/create, /game/add-bot and
-- /game/create-solo routes. Integrity is backstopped by the games CHECK/UNIQUE/FK
-- constraints; policy lives in the edge function.
--
-- Naming: engine_* = service-role, EF-only gated RPCs (REVOKEd from
-- authenticated). cron_* = pg_cron-scheduled private jobs. app_* =
-- client-direct RPCs (PostgREST, under RLS/auth). do_*/other private.* =
-- internal helpers. See docs/engine_architecture.md.
-- ============================================

-- ============================================
-- RPC: engine_create_game
-- Creates a game and adds the creator as participant (index 0).
-- game_states and observations are not created until /game/start.
-- ============================================
-- RPC: engine_create_game — the EF /game/create route's gated write, a thin
-- atomic writer. The EF is authoritative for policy: it validates timing/players,
-- gates guests, derives the rating pool (GameRules.ratingPool → p_pool), and
-- validates the client's rated assertion (→ p_rated). Integrity is guaranteed by
-- the `games` CHECK constraints (timing_mode_exclusive, increment_requires_budget,
-- player_count_valid, rated_pool_consistent, bounds) and the short_code UNIQUE,
-- so this function does not re-check those. It only generates a unique short_code
-- and seats the creator as participant 0. Gated to the service role (the EF is
-- the only caller); the caller's verified id arrives as p_caller_id.
CREATE OR REPLACE FUNCTION public.engine_create_game(
  p_caller_id         UUID,
  p_min_players       INT,
  p_max_players       INT,
  p_schema_version    INT,
  p_access            public.game_access,
  p_turn_seconds      INT,
  p_budget_seconds    INT,
  p_increment_seconds INT,
  p_config            JSONB,
  -- Whether the game is rated. The EF computes this authoritatively (eligible
  -- pool AND a registered caller) and validates it against the client's
  -- assertion; the client cannot forge it.
  p_rated             BOOLEAN,
  -- Pool name from GameRules.ratingPool (NULL ⇒ unrated), computed in the EF.
  p_pool              TEXT
)
RETURNS UUID AS $$
DECLARE
  v_game_id UUID;
BEGIN
  <<loop_label>>
  LOOP
    BEGIN
      INSERT INTO public.games
        (created_by, access, turn_seconds, budget_seconds, increment_seconds,
         min_players, max_players, config, schema_version, short_code, rated, rating_pool)
      VALUES (
        p_caller_id,
        p_access,
        p_turn_seconds,
        p_budget_seconds,
        p_increment_seconds,
        p_min_players,
        p_max_players,
        p_config,
        p_schema_version,
        upper(substring(md5(random()::text) from 1 for 6)),
        p_rated,
        p_pool
      )
      RETURNING id INTO v_game_id;
      EXIT loop_label;
    EXCEPTION WHEN unique_violation THEN
      -- Loop and try a new random short_code
    END;
  END LOOP;

  INSERT INTO public.participants (game_id, user_id, player_index)
  VALUES (v_game_id, p_caller_id, 0);

  RETURN v_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.engine_create_game(UUID, INT, INT, INT, public.game_access, INT, INT, INT, JSONB, BOOLEAN, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.engine_create_game(UUID, INT, INT, INT, public.game_access, INT, INT, INT, JSONB, BOOLEAN, TEXT) TO service_role;

-- ============================================
-- Bot seating
-- ============================================
-- Seats a *server* bot into an open seat of a waiting/ready game. Shared by
-- engine_add_bot_to_game (host-driven, with a creator check) and, later,
-- matchmaking auto-fill (service-role). Caller must hold the games row lock.
-- Enforces the server-bots-only + schema + rated invariants. Config seatability
-- (the game's botSeatable rule) is gated by the EF in TypeScript
-- (GameRules.botSeatable) before this runs. Local bots are NEVER seated here;
-- they go only through engine_create_solo_game (sole-human games).
CREATE OR REPLACE FUNCTION private.seat_server_bot(p_game_id UUID, p_bot_id UUID)
RETURNS VOID AS $$
DECLARE
  v_status         public.game_status;
  v_schema_version INT;
  v_max_players    INT;
  v_min_players    INT;
  v_rated          BOOLEAN;
  v_turn_seconds   INT;
  v_budget_seconds INT;
  v_game_config    JSONB;
  v_count          INT;
  v_bot            RECORD;
BEGIN
  SELECT status, schema_version, max_players, min_players, rated,
         turn_seconds, budget_seconds, config
  INTO v_status, v_schema_version, v_max_players, v_min_players, v_rated,
       v_turn_seconds, v_budget_seconds, v_game_config
  FROM public.games WHERE id = p_game_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Game not found' USING ERRCODE = 'EIG06'; END IF;
  IF v_status NOT IN ('waiting', 'ready') THEN
    RAISE EXCEPTION 'Game is not accepting players' USING ERRCODE = 'EIG10';
  END IF;
  -- Timing guard (invariant 4): a server bot's endpoint may be unreachable,
  -- and the expiry sweep is the retry for a lost wake — which only exists
  -- when the game has a turn deadline. Every caller of this function seats
  -- server bots, so the game must be timed.
  IF v_turn_seconds IS NULL AND v_budget_seconds IS NULL THEN
    RAISE EXCEPTION 'A game with a server bot must be timed';
  END IF;

  SELECT schema_version, is_local, rated_eligible, config
  INTO v_bot
  FROM public.bots WHERE id = p_bot_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Bot not found'; END IF;
  -- Server bots only (a local bot is client-driven). Multiplayer/host-fill must
  -- never seat a client-driven bot — that is invariant 2.
  IF v_bot.is_local THEN
    RAISE EXCEPTION 'Only server bots can be added to a game';
  END IF;
  -- Schema gate, mirroring the human join gate.
  IF v_schema_version > v_bot.schema_version THEN
    RAISE EXCEPTION 'Bot does not support this game schema (game %, bot up to %)',
      v_schema_version, v_bot.schema_version;
  END IF;
  -- Rated guard (invariant 3): reject, never downgrade.
  IF v_rated AND NOT v_bot.rated_eligible THEN
    RAISE EXCEPTION 'This bot is not eligible for rated games';
  END IF;
  -- Config seatability (the game's botSeatable rule) is gated upstream by the EF
  -- in TypeScript before this RPC is called, so it is not re-checked here.

  -- A bot identity may hold several seats: the wake and the bot/action route
  -- carry player_index, so seats are unambiguous, and the rating pipeline treats each
  -- seat as an independent result for the identity. So no one-seat-per-bot guard —
  -- only the full-game cap below bounds it.
  SELECT COUNT(*) INTO v_count
  FROM public.participants WHERE game_id = p_game_id;
  IF v_count >= v_max_players THEN
    RAISE EXCEPTION 'Game is full' USING ERRCODE = 'EIG08';
  END IF;

  INSERT INTO public.participants (game_id, bot_id, player_index)
  VALUES (p_game_id, p_bot_id, v_count);

  IF v_count + 1 >= v_min_players THEN
    UPDATE public.games SET status = 'ready' WHERE id = p_game_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- RPC: engine_add_bot_to_game — the EF /game/add-bot route's gated write. The
-- host's waiting-room "Add bot": server bots only; the EF rejects guests (server
-- bots cost per-move compute) and gates config seatability
-- (GameRules.botSeatable) in TypeScript. This function holds the games lock for
-- the creator check + seat-count cap; the bot-class invariants + seat logic live
-- in seat_server_bot (all riding that required lock). Gated to the service role;
-- the verified caller arrives as p_caller_id.
CREATE OR REPLACE FUNCTION public.engine_add_bot_to_game(
  p_caller_id UUID,
  p_game_id   UUID,
  p_bot_id    UUID
)
RETURNS VOID AS $$
DECLARE
  v_created_by UUID;
BEGIN
  SELECT created_by INTO v_created_by
  FROM public.games WHERE id = p_game_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Game not found' USING ERRCODE = 'EIG06'; END IF;
  IF v_created_by IS NULL OR v_created_by != p_caller_id THEN
    RAISE EXCEPTION 'Only the game creator can add a bot';
  END IF;

  PERFORM private.seat_server_bot(p_game_id, p_bot_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.engine_add_bot_to_game(UUID, UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.engine_add_bot_to_game(UUID, UUID, UUID) TO service_role;

-- RPC: engine_create_solo_game — the EF /game/create-solo route's gated write, a
-- thin atomic writer. Creates an unrated, private game with the caller as the
-- SOLE human and seats the given bots (in array order) full at creation, so it is
-- never joinable (a local bot only ever exists in a sole-human game — invariant
-- 1). The EF owns all bot-class policy in TypeScript before this runs: config
-- seatability (GameRules.botSeatable), schema compatibility, guests-may-seat-
-- local-bots-only, and the "server bot ⇒ timed / local bot ⇒ untimed" rules
-- (these have no SQL backstop and live purely in TS). Bot existence is guaranteed
-- by the participant→bots FK. The client calls /game/start next. Gated to the
-- service role; verified caller as p_caller_id.
CREATE OR REPLACE FUNCTION public.engine_create_solo_game(
  p_caller_id         UUID,
  p_bot_ids           UUID[],
  p_schema_version    INT,
  p_turn_seconds      INT   DEFAULT NULL,
  p_budget_seconds    INT   DEFAULT NULL,
  p_increment_seconds INT   DEFAULT NULL,
  p_config            JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID AS $$
DECLARE
  v_game_id UUID;
  v_total   INT;
  v_bot_id  UUID;
  v_idx     INT;
BEGIN
  v_total := 1 + array_length(p_bot_ids, 1);  -- the human + the bots

  -- Both local and server bots may fill several seats: local bots resolve by
  -- player_index, and server bots carry player_index through the wake and
  -- the bot/action route, so the same identity in multiple seats is unambiguous.

  -- Private + unrated; min=max=total so it is full at creation and never accepts
  -- another human. Retry the short_code on the rare collision (UNIQUE NOT NULL).
  <<loop_label>>
  LOOP
    BEGIN
      INSERT INTO public.games
        (created_by, access, turn_seconds, budget_seconds, increment_seconds,
         min_players, max_players, config, schema_version, short_code, rated, rating_pool)
      VALUES (
        p_caller_id, 'private', p_turn_seconds, p_budget_seconds, p_increment_seconds,
        v_total, v_total, COALESCE(p_config, '{}'::jsonb), p_schema_version,
        upper(substring(md5(random()::text) from 1 for 6)), false, NULL
      )
      RETURNING id INTO v_game_id;
      EXIT loop_label;
    EXCEPTION WHEN unique_violation THEN
      -- new short_code
    END;
  END LOOP;

  INSERT INTO public.participants (game_id, user_id, player_index)
  VALUES (v_game_id, p_caller_id, 0);

  v_idx := 1;
  FOREACH v_bot_id IN ARRAY p_bot_ids LOOP
    INSERT INTO public.participants (game_id, bot_id, player_index)
    VALUES (v_game_id, v_bot_id, v_idx);
    v_idx := v_idx + 1;
  END LOOP;

  -- Full at creation (min=max=total), so never joinable by another human. Left
  -- in 'ready'; the client calls the game /start route to compute the
  -- initial state and begin play (start logic moved to the EF / TS rules).
  UPDATE public.games SET status = 'ready' WHERE id = v_game_id;

  RETURN v_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.engine_create_solo_game(UUID, UUID[], INT, INT, INT, INT, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.engine_create_solo_game(UUID, UUID[], INT, INT, INT, INT, JSONB) TO service_role;
