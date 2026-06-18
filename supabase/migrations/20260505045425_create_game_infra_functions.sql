-- ============================================
-- GAME INFRASTRUCTURE FUNCTIONS
-- ============================================
-- Game-agnostic RPC functions. Call into the three game-specific hooks
-- (game_initial_state, game_compute_observation, game_apply_action) which
-- are defined in the implementation migration applied before this one.
-- ============================================

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

-- Require authentication, returns user_id or raises exception
CREATE OR REPLACE FUNCTION private.require_auth()
RETURNS UUID AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  RETURN v_user_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

-- Get participant for a user in a game (returns record with id and player_index)
CREATE OR REPLACE FUNCTION private.get_participant(p_game_id UUID, p_user_id UUID)
RETURNS TABLE(participant_id UUID, player_index INT) AS $$
  SELECT id, player_index
  FROM public.participants
  WHERE game_id = p_game_id AND user_id = p_user_id;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '';

-- Require participant in game, raises if not found
CREATE OR REPLACE FUNCTION private.require_participant(p_game_id UUID, p_user_id UUID)
RETURNS TABLE(participant_id UUID, player_index INT) AS $$
DECLARE
  v_result RECORD;
BEGIN
  SELECT * INTO v_result FROM private.get_participant(p_game_id, p_user_id);
  IF v_result.participant_id IS NULL THEN
    RAISE EXCEPTION 'Not a participant in this game';
  END IF;
  RETURN QUERY SELECT v_result.participant_id, v_result.player_index;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

-- Require game is in 'active' status
CREATE OR REPLACE FUNCTION private.require_active_game(p_game_id UUID)
RETURNS VOID AS $$
DECLARE
  v_status public.game_status;
BEGIN
  SELECT status INTO v_status FROM public.games WHERE id = p_game_id;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Game not found';
  END IF;
  IF v_status != 'active' THEN
    RAISE EXCEPTION 'Game is not active';
  END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

-- Validate version for optimistic locking.
-- Called after the FOR UPDATE lock on games and the latest game_states read,
-- so the current version is already in the caller's local variable.
CREATE OR REPLACE FUNCTION private.validate_version(
  p_current_version  INT,
  p_expected_version INT
)
RETURNS VOID AS $$
BEGIN
  IF p_current_version != p_expected_version THEN
    RAISE EXCEPTION 'Stale state: expected version %, current %',
      p_expected_version, p_current_version;
  END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

-- Fans out per-player observation slices after every state change.
-- Calls game_compute_observation once per participant so hidden-info games
-- can write different slices (e.g. Poker hole cards, Literature hands).
CREATE OR REPLACE FUNCTION private.update_all_observations(
  p_game_id         UUID,
  p_new_state       JSONB,
  p_new_pending     INT[],
  p_new_version     INT,
  p_config          JSONB,
  p_schema_version  INT,
  p_new_deadline    TIMESTAMPTZ DEFAULT NULL,
  p_player_times    BIGINT[]    DEFAULT NULL,
  p_turn_started_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_rec   RECORD;
  v_obs   JSONB;
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM public.participants
  WHERE game_id = p_game_id;

  FOR v_rec IN
    SELECT user_id, player_index
    FROM public.participants
    WHERE game_id = p_game_id AND user_id IS NOT NULL
    ORDER BY player_index
  LOOP
    v_obs := private.game_compute_observation(
      p_new_state,
      p_new_pending,
      v_rec.player_index,
      v_count,
      p_config,
      p_schema_version
    );

    UPDATE public.observations
    SET data            = v_obs->'data',
        pending_players = ARRAY(
          SELECT jsonb_array_elements_text(v_obs->'pending_players')::INT
        ),
        version         = p_new_version,
        turn_deadline   = p_new_deadline,
        player_times    = p_player_times,
        turn_started_at = p_turn_started_at,
        updated_at      = NOW()
    WHERE game_id = p_game_id
      AND user_id  = v_rec.user_id;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Xorshift64 PRNG. Given a seed, returns the next pseudo-random value and
-- the advanced seed to store back into game_states. Uses only XOR and bit
-- shifts — no integer overflow possible on PostgreSQL BIGINT.
--
-- Usage inside game_apply_action:
--   DECLARE r RECORD;
--   SELECT * INTO r FROM private.prng_next(p_rng_seed);
--   -- r.value is your random BIGINT; r.next_seed is the seed to pass on
--   p_rng_seed := r.next_seed;  -- chain calls for multiple values
--
-- Precondition: p_seed != 0. Zero is a fixed point (always returns 0).
-- start_game guarantees the initial seed is non-zero.
CREATE OR REPLACE FUNCTION private.prng_next(p_seed BIGINT)
RETURNS TABLE(value BIGINT, next_seed BIGINT) AS $$
DECLARE
  x BIGINT := p_seed;
BEGIN
  x := x # (x << 13);
  x := x # (x >> 7);
  x := x # (x << 17);
  value     := x;
  next_seed := x;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path = '';

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Writes game_outcomes rows and marks the game finished.
-- Owns the outcome → game_outcomes → games.status pipeline so it is
-- never duplicated across submit_action and expire_turn.
CREATE OR REPLACE FUNCTION private.finish_game(p_game_id UUID, p_outcome JSONB)
RETURNS VOID AS $$
DECLARE
  v_player_idx      INT;
  v_result_str      TEXT;
  v_score           NUMERIC;
  v_placement       INT;
  v_team_index      INT;
  v_outcome_user_id UUID;
  v_outcome_bot_id  UUID;
BEGIN
  IF jsonb_typeof(p_outcome) != 'array' THEN
    RAISE EXCEPTION 'game_apply_action returned non-array outcome';
  END IF;

  FOR v_player_idx, v_result_str, v_score, v_placement, v_team_index IN
    SELECT
      (elem->>'player_index')::INT,
      elem->>'result',
      (elem->>'score')::NUMERIC,
      (elem->>'placement')::INT,
      (elem->>'team_index')::INT
    FROM jsonb_array_elements(p_outcome) AS elem
  LOOP
    SELECT user_id, bot_id
    INTO v_outcome_user_id, v_outcome_bot_id
    FROM public.participants
    WHERE game_id = p_game_id AND player_index = v_player_idx;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Outcome references unknown player_index %', v_player_idx;
    END IF;
    IF v_placement IS NULL THEN
      RAISE EXCEPTION 'Outcome for player_index % missing required placement', v_player_idx;
    END IF;
    IF v_team_index IS NULL THEN
      RAISE EXCEPTION 'Outcome for player_index % missing required team_index', v_player_idx;
    END IF;

    INSERT INTO public.game_outcomes
      (game_id, player_index, user_id, bot_id, result, score, placement, team_index)
    VALUES
      (p_game_id, v_player_idx, v_outcome_user_id, v_outcome_bot_id,
       v_result_str::public.game_result, v_score, v_placement, v_team_index);
  END LOOP;

  UPDATE public.games
  SET status = 'finished', finished_at = NOW()
  WHERE id = p_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Computes the deadline and turn_started_at for the next action.
-- Centralises the precedence chain used by start_game, submit_action,
-- and expire_turn. Pass p_outcome = NULL when no game-over has occurred.
CREATE OR REPLACE FUNCTION private.compute_next_deadline(
  p_outcome          JSONB,
  p_action_seconds   INT,
  p_budget_seconds   INT,
  p_turn_seconds     INT,
  p_new_pending      INT[],
  p_new_player_times BIGINT[]
)
RETURNS TABLE(deadline TIMESTAMPTZ, turn_started_at TIMESTAMPTZ) AS $$
BEGIN
  turn_started_at := CASE
    WHEN p_outcome IS NOT NULL THEN NULL
    WHEN p_action_seconds IS NOT NULL
      OR p_budget_seconds IS NOT NULL
      OR p_turn_seconds   IS NOT NULL THEN NOW()
    ELSE NULL
  END;

  deadline := CASE
    WHEN p_outcome IS NOT NULL THEN NULL
    WHEN p_action_seconds IS NOT NULL
      THEN NOW() + (p_action_seconds * interval '1 second')
    -- Use the minimum remaining budget across all pending players so the
    -- deadline fires as soon as the first player's clock runs out.
    -- NOTE: budget mode with multiple simultaneous pending players is unsupported
    -- by the framework (BudgetConfig is restricted to sequential games).
    -- This MIN is a best-effort safeguard; expire_turn still drains all pending
    -- players' banks when it fires, not just the one who ran out first.
    WHEN p_budget_seconds IS NOT NULL AND cardinality(p_new_pending) > 0
      THEN NOW() + (
        (SELECT MIN(p_new_player_times[idx + 1])
         FROM unnest(p_new_pending) AS idx)::NUMERIC / 1000 * interval '1 second'
      )
    WHEN p_turn_seconds IS NOT NULL
      THEN NOW() + (p_turn_seconds * interval '1 second')
    ELSE NULL
  END;

  RETURN NEXT;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

-- Persists the result of one applied action:
--   1. Computes deadline via compute_next_deadline.
--   2. Inserts new game_states row (append-only history).
--   3. Records the action in the actions log.
--   4. Fans out per-player observations.
--   5. Calls finish_game when outcome is non-null.
--
-- Called by submit_action (once) and expire_turn (once per pending player).
-- The only differences between the two callers are bank deduction (done
-- before this call) and the action type / user_id / data passed in.
CREATE OR REPLACE FUNCTION private.commit_action(
  p_game_id          UUID,
  p_acting_user_id   UUID,    -- NULL for bot/system actions
  p_acting_bot_id    UUID,    -- NULL for user/system actions
  p_action_type      TEXT,    -- 'user' | 'bot' | 'system'
  p_action_data      JSONB,
  p_new_state        JSONB,
  p_new_pending      INT[],
  p_new_version      INT,
  p_new_seed         BIGINT,
  p_new_player_times BIGINT[],
  p_config           JSONB,
  p_schema_version   INT,
  p_outcome          JSONB,
  p_action_seconds   INT,
  p_budget_seconds   INT,
  p_turn_seconds     INT,
  p_player_index     INT      -- seat index of the acting player; NULL for anonymous system actions
)
RETURNS VOID AS $$
DECLARE
  v_dl RECORD;
BEGIN
  SELECT * INTO v_dl FROM private.compute_next_deadline(
    p_outcome, p_action_seconds, p_budget_seconds, p_turn_seconds,
    p_new_pending, p_new_player_times
  );

  -- Append new state row — game_states is the immutable history.
  INSERT INTO public.game_states
    (game_id, version, state, pending_players, rng_seed,
     turn_deadline, player_times, turn_started_at)
  VALUES
    (p_game_id, p_new_version, p_new_state, p_new_pending, p_new_seed,
     v_dl.deadline, p_new_player_times, v_dl.turn_started_at);

  INSERT INTO public.actions (game_id, user_id, bot_id, type, data, player_index, version_after)
  VALUES (p_game_id, p_acting_user_id, p_acting_bot_id, p_action_type::public.action_type,
          p_action_data, p_player_index, p_new_version);

  -- finish_game updates games.status before update_all_observations so that
  -- the games realtime event always precedes the observations event. Clients
  -- gate outcome rendering on status='finished', so this ordering prevents a
  -- brief window where the client sees empty pending_players on an 'active' game.
  IF p_outcome IS NOT NULL THEN
    PERFORM private.finish_game(p_game_id, p_outcome);
  END IF;

  PERFORM private.update_all_observations(
    p_game_id, p_new_state, p_new_pending, p_new_version, p_config,
    p_schema_version,
    v_dl.deadline, p_new_player_times, v_dl.turn_started_at
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- RPC: create_game
-- Creates game and adds creator as participant (index 0).
-- game_states and observations are not created until start_game.
-- ============================================
CREATE OR REPLACE FUNCTION public.create_game(
  -- Game-specific, required (no defaults): the game module always supplies these.
  -- Player counts come from GameModule.creationSpec/playersForConfig; the schema
  -- version from GameModule.schemaVersion. Required params must precede the
  -- defaulted ones below.
  p_min_players       INT,
  p_max_players       INT,
  p_schema_version    INT,
  -- Infra-level, safe to default: untimed unless a timer is given, public,
  -- unrated-unless-eligible. (Server still derives the real pool/rated flag.)
  p_access            public.game_access DEFAULT 'public',
  p_turn_seconds      INT     DEFAULT NULL,
  p_budget_seconds    INT     DEFAULT NULL,
  p_increment_seconds INT     DEFAULT NULL,
  -- Opaque, game-owned config blob. Always an object; defaults to empty ({})
  -- for games with no creation parameters. Whether specific keys are required
  -- is the game's concern (validated in game_initial_state / the game's config
  -- model), not infra's.
  p_config            JSONB   DEFAULT '{}'::jsonb,
  -- Client supplies a preference only; the server derives the actual pool via
  -- game_rating_pool() so clients cannot forge a pool or enable rating on an
  -- ineligible game.
  p_rated_preference  BOOLEAN DEFAULT true
)
RETURNS UUID AS $$
DECLARE
  v_game_id UUID;
  v_user_id UUID;
  v_pool    TEXT;
  v_rated   BOOLEAN;
BEGIN
  v_user_id := private.require_auth();

  IF p_turn_seconds IS NOT NULL AND p_budget_seconds IS NOT NULL THEN
    RAISE EXCEPTION 'turn_seconds and budget_seconds are mutually exclusive';
  END IF;
  IF p_increment_seconds IS NOT NULL AND p_budget_seconds IS NULL THEN
    RAISE EXCEPTION 'increment_seconds requires budget_seconds';
  END IF;
  IF p_min_players < 1 OR p_max_players < p_min_players THEN
    RAISE EXCEPTION 'Invalid player count: min_players=%, max_players=%',
      p_min_players, p_max_players;
  END IF;

  v_pool  := private.game_rating_pool(
               p_access, p_turn_seconds, p_budget_seconds, p_increment_seconds,
               p_min_players, p_max_players, COALESCE(p_config, '{}'::jsonb)
             );
  -- Guests (anonymous users) play unrated regardless of preference or pool.
  v_rated := p_rated_preference AND v_pool IS NOT NULL
             AND NOT private.is_anonymous();

  <<loop_label>>
  LOOP
    BEGIN
      INSERT INTO public.games
        (created_by, access, turn_seconds, budget_seconds, increment_seconds,
         min_players, max_players, config, schema_version, short_code, rated, rating_pool)
      VALUES (
        v_user_id,
        p_access,
        p_turn_seconds,
        p_budget_seconds,
        p_increment_seconds,
        p_min_players,
        p_max_players,
        p_config,
        p_schema_version,
        upper(substring(md5(random()::text) from 1 for 6)),
        v_rated,
        v_pool
      )
      RETURNING id INTO v_game_id;
      EXIT loop_label;
    EXCEPTION WHEN unique_violation THEN
      -- Loop and try a new random short_code
    END;
  END LOOP;

  INSERT INTO public.participants (game_id, user_id, player_index)
  VALUES (v_game_id, v_user_id, 0);

  RETURN v_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- RPC: join_game
-- Adds participant; transitions to 'ready' when player count is met.
-- ============================================
-- p_client_schema_version: the joining client's highest supported game schema
-- (GameModule.schemaVersion). Required, not defaulted: the server refuses to seat
-- a player in a game whose schema_version exceeds it, so a client never becomes a
-- participant in a game it cannot render. Omitting it fails function resolution
-- rather than silently skipping the gate — there is no caller that joins without a
-- known schema (every app build ships exactly one GameModule, and bots are seated
-- directly elsewhere, not via join_game). This is the only schema gate covering
-- all join paths (lobby, friends, by-code, deep link) atomically, since it runs
-- under the same FOR UPDATE lock as the seat INSERT.
CREATE OR REPLACE FUNCTION public.join_game(
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
  -- Without FOR UPDATE a concurrent start_game could commit (status='active')
  -- between this read and the participant INSERT, leaving a participant with
  -- no observation row.
  SELECT status, access, created_by, min_players, max_players, schema_version,
         rated
  INTO v_game_status, v_access, v_created_by, v_min_players, v_max_players,
       v_schema_version, v_rated
  FROM public.games WHERE id = p_game_id
  FOR UPDATE;

  IF v_game_status IS NULL THEN
    RAISE EXCEPTION 'Game not found';
  END IF;

  IF v_schema_version > p_client_schema_version THEN
    RAISE EXCEPTION 'Unsupported game schema: game requires schema %, client supports up to %',
      v_schema_version, p_client_schema_version;
  END IF;

  IF v_game_status NOT IN ('waiting', 'ready') THEN
    RAISE EXCEPTION 'Game is not accepting players';
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
      RAISE EXCEPTION 'Only friends of the creator can join this game';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.participants
    WHERE game_id = p_game_id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Already joined this game';
  END IF;

  SELECT COUNT(*) INTO v_participant_count
  FROM public.participants WHERE game_id = p_game_id;

  IF v_participant_count >= v_max_players THEN
    RAISE EXCEPTION 'Game is full';
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
-- RPC: start_game
-- Calls game_initial_state(), creates game_states and per-player observations,
-- transitions to 'active'.
-- ============================================
CREATE OR REPLACE FUNCTION public.start_game(p_game_id UUID)
RETURNS VOID AS $$
DECLARE
  v_user_id              UUID;
  v_created_by           UUID;
  v_status               public.game_status;
  v_config               JSONB;
  v_turn_seconds         INT;
  v_budget_seconds       INT;
  v_increment_seconds    INT;
  v_min_players          INT;
  v_action_seconds       INT;
  v_initial              JSONB;
  v_initial_state        JSONB;
  v_initial_pending      INT[];
  v_initial_deadline     TIMESTAMPTZ;
  v_initial_player_times BIGINT[];
  v_initial_turn_started TIMESTAMPTZ;
  v_seed                 BIGINT;
  v_count                INT;
  v_schema_version       INT;
  v_rec                  RECORD;
  v_obs                  JSONB;
  v_dl                   RECORD;
  i                      INT;
BEGIN
  v_user_id := private.require_auth();

  -- Lock the game row for the duration of start_game so a concurrent
  -- leave_game cannot remove a participant between the status check and
  -- the game_states / observations inserts.
  SELECT created_by, status, config, turn_seconds, budget_seconds,
         increment_seconds, min_players, schema_version
  INTO v_created_by, v_status, v_config, v_turn_seconds, v_budget_seconds,
       v_increment_seconds, v_min_players, v_schema_version
  FROM public.games WHERE id = p_game_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Game not found';
  END IF;
  IF v_created_by IS NULL OR v_created_by != v_user_id THEN
    RAISE EXCEPTION 'Only the game creator can start the game';
  END IF;
  IF v_status != 'ready' THEN
    RAISE EXCEPTION 'Game is not ready to start';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.participants WHERE game_id = p_game_id;

  IF v_count < v_min_players THEN
    RAISE EXCEPTION 'Not enough players to start (% of % required)',
      v_count, v_min_players;
  END IF;

  -- Single random() call per game. Passed to game_initial_state so setup
  -- randomness (shuffle, deal) also derives from it deterministically.
  v_seed := greatest(floor(random() * 9223372036854775807)::BIGINT, 1);

  v_initial       := private.game_initial_state(
    v_seed, v_config, v_count, v_schema_version
  );
  v_initial_state := v_initial->'state';
  IF v_initial_state IS NULL OR jsonb_typeof(v_initial_state) = 'null' THEN
    RAISE EXCEPTION 'game_initial_state must return a non-null state';
  END IF;
  IF jsonb_typeof(v_initial->'pending_players') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'game_initial_state must return pending_players as a JSON array';
  END IF;
  v_initial_pending := ARRAY(
    SELECT jsonb_array_elements_text(v_initial->'pending_players')::INT
  );
  -- game_initial_state advances the seed for any setup randomness it consumes.
  -- Store the returned seed so game_apply_action continues from where setup left off.
  v_seed := (v_initial->>'rng_seed')::BIGINT;
  IF v_seed IS NULL OR v_seed = 0 THEN
    RAISE EXCEPTION 'game_initial_state must return a non-zero rng_seed';
  END IF;

  -- Initialise per-player bank if budget mode, one entry per player (1-indexed).
  IF v_budget_seconds IS NOT NULL THEN
    v_initial_player_times := ARRAY[]::BIGINT[];
    FOR i IN 1..v_count LOOP
      v_initial_player_times := v_initial_player_times || (v_budget_seconds * 1000)::BIGINT;
    END LOOP;
  END IF;

  -- Hook may return turn_seconds to override the game default for the first turn.
  v_action_seconds := (v_initial->>'turn_seconds')::INT;

  SELECT * INTO v_dl FROM private.compute_next_deadline(
    NULL,  -- no outcome at game start
    v_action_seconds, v_budget_seconds, v_turn_seconds,
    v_initial_pending, v_initial_player_times
  );
  v_initial_deadline     := v_dl.deadline;
  v_initial_turn_started := v_dl.turn_started_at;

  INSERT INTO public.game_states
    (game_id, version, state, pending_players, rng_seed, turn_deadline, player_times, turn_started_at)
  VALUES
    (p_game_id, 0, v_initial_state, v_initial_pending, v_seed,
     v_initial_deadline, v_initial_player_times, v_initial_turn_started);

  FOR v_rec IN
    SELECT user_id, player_index
    FROM public.participants
    WHERE game_id = p_game_id AND user_id IS NOT NULL
    ORDER BY player_index
  LOOP
    v_obs := private.game_compute_observation(
      v_initial_state,
      v_initial_pending,
      v_rec.player_index,
      v_count,
      v_config,
      v_schema_version
    );

    INSERT INTO public.observations
      (game_id, user_id, data, pending_players, version, turn_deadline, player_times, turn_started_at)
    VALUES (
      p_game_id,
      v_rec.user_id,
      v_obs->'data',
      ARRAY(SELECT jsonb_array_elements_text(v_obs->'pending_players')::INT),
      0,
      v_initial_deadline,
      v_initial_player_times,
      v_initial_turn_started
    );
  END LOOP;

  UPDATE public.games SET status = 'active' WHERE id = p_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- RPC: trigger_turn_expiry
-- Called by a client that has detected the turn deadline has passed.
-- Delegates to private.expire_turn, which re-validates under lock so
-- concurrent calls (client + cron) are safe.
-- ============================================
CREATE OR REPLACE FUNCTION public.trigger_turn_expiry(p_game_id UUID)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := private.require_auth();
  PERFORM private.require_active_game(p_game_id);
  PERFORM private.require_participant(p_game_id, v_user_id);
  PERFORM private.expire_turn(p_game_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- RPC: cancel_game
-- Aborts a waiting or ready game (creator only).
-- ============================================
-- Core cancel logic, parameterised by the acting user. Shared by the public
-- cancel_game RPC (caller = auth.uid()) and private.purge_user (acting on
-- another user during account deletion / stale-guest cleanup).
CREATE OR REPLACE FUNCTION private.do_cancel_game(p_game_id UUID, p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_created_by UUID;
  v_status     public.game_status;
BEGIN
  SELECT created_by, status INTO v_created_by, v_status
  FROM public.games WHERE id = p_game_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Game not found';
  END IF;
  IF v_created_by IS NULL OR v_created_by != p_user_id THEN
    RAISE EXCEPTION 'Only the game creator can cancel the game';
  END IF;
  IF v_status NOT IN ('waiting', 'ready') THEN
    RAISE EXCEPTION 'Can only cancel a game that has not started';
  END IF;

  UPDATE public.games
  SET status = 'aborted', finished_at = NOW()
  WHERE id = p_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.cancel_game(p_game_id UUID)
RETURNS VOID AS $$
BEGIN
  PERFORM private.do_cancel_game(p_game_id, private.require_auth());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- RPC: leave_game
-- Non-creator participant leaves a waiting or ready game.
-- Compacts player_index values so no gaps exist for the next joiner.
-- Transitions ready → waiting if the count drops below min_players.
-- The creator cannot leave — use cancel_game instead.
-- ============================================
-- Core leave logic, parameterised by the acting user. Shared by the public
-- leave_game RPC and private.purge_user.
CREATE OR REPLACE FUNCTION private.do_leave_game(p_game_id UUID, p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_created_by  UUID;
  v_status      public.game_status;
  v_min_players INT;
  v_participant RECORD;
  v_new_count   INT;
BEGIN
  -- Lock the game row to serialise concurrent leave operations on the same game.
  -- Without this, two simultaneous leaves can produce stale player_index reads,
  -- causing compaction to leave gaps that break subsequent joins.
  SELECT created_by, status, min_players
  INTO v_created_by, v_status, v_min_players
  FROM public.games WHERE id = p_game_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Game not found';
  END IF;
  IF v_created_by = p_user_id THEN
    RAISE EXCEPTION 'Creator cannot leave — use cancel_game instead';
  END IF;
  IF v_status NOT IN ('waiting', 'ready') THEN
    RAISE EXCEPTION 'Can only leave a game that has not started';
  END IF;

  SELECT * INTO v_participant FROM private.require_participant(p_game_id, p_user_id);

  DELETE FROM public.participants
  WHERE game_id = p_game_id AND user_id = p_user_id;

  -- Compact: shift down all participants with a higher index so seats stay
  -- contiguous (0..n-1) after a mid-lobby leave.
  UPDATE public.participants
  SET player_index = player_index - 1
  WHERE game_id = p_game_id AND player_index > v_participant.player_index;

  SELECT COUNT(*) INTO v_new_count
  FROM public.participants WHERE game_id = p_game_id;

  IF v_new_count < v_min_players THEN
    UPDATE public.games SET status = 'waiting' WHERE id = p_game_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.leave_game(p_game_id UUID)
RETURNS VOID AS $$
BEGIN
  PERFORM private.do_leave_game(p_game_id, private.require_auth());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- RPC: forfeit_game
-- Player voluntarily forfeits an active game.
-- Out-of-turn (no pending_players check — any participant can forfeit).
-- No version check: forfeiting is an unconditional intent, and the
-- FOR UPDATE lock on games already serialises it against concurrent
-- actions — commit_action assigns the next version under that lock,
-- so replays remain complete and ordered.
-- Records a 'system' action with the forfeiting user_id populated.
-- ============================================
-- Core forfeit logic, parameterised by the acting user. Shared by the public
-- forfeit_game RPC and private.purge_user (which forfeits a departing user's
-- active games so outcomes, observations, and rating triggers fire normally).
CREATE OR REPLACE FUNCTION private.do_forfeit_game(p_game_id UUID, p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_participant          RECORD;
  v_status               public.game_status;
  v_config               JSONB;
  v_turn_seconds         INT;
  v_budget_seconds       INT;
  v_schema_version       INT;
  v_current_state        JSONB;
  v_current_pending      INT[];
  v_current_version      INT;
  v_current_seed         BIGINT;
  v_current_player_times BIGINT[];
  v_new_version          INT;
  v_new_seed             BIGINT;
  v_result               JSONB;
  v_new_state            JSONB;
  v_new_pending          INT[];
  v_outcome              JSONB;
  v_action_data          JSONB;
BEGIN
  SELECT * INTO v_participant FROM private.require_participant(p_game_id, p_user_id);

  -- Acquire lock and check status atomically — no TOCTOU window between
  -- the active check and the lock.
  SELECT status, config, turn_seconds, budget_seconds, schema_version
  INTO v_status, v_config, v_turn_seconds, v_budget_seconds, v_schema_version
  FROM public.games WHERE id = p_game_id
  FOR UPDATE;

  IF v_status IS NULL THEN RAISE EXCEPTION 'Game not found'; END IF;
  IF v_status != 'active' THEN RAISE EXCEPTION 'Game is not active'; END IF;

  -- Read latest state — no FOR UPDATE needed, games row is already locked.
  SELECT state, pending_players, version, rng_seed, player_times
  INTO v_current_state, v_current_pending, v_current_version, v_current_seed,
       v_current_player_times
  FROM public.game_states
  WHERE game_id = p_game_id
  ORDER BY version DESC
  LIMIT 1;

  v_action_data := jsonb_build_object(
    'type',         'forfeit',
    'player_index', v_participant.player_index
  );

  v_result := private.game_handle_system_action(
    v_current_state,
    v_current_pending,
    'forfeit'::public.system_action_type,
    v_action_data,
    v_current_seed,
    v_config,
    v_schema_version
  );

  v_new_state   := v_result->'state';
  v_new_pending := ARRAY(SELECT jsonb_array_elements_text(v_result->'pending_players')::INT);
  v_outcome     := v_result->'outcome';
  v_new_seed    := (v_result->>'rng_seed')::BIGINT;
  IF v_new_seed IS NULL OR v_new_seed = 0 THEN
    RAISE EXCEPTION 'game_handle_system_action must return a non-zero rng_seed';
  END IF;
  v_new_version := v_current_version + 1;

  PERFORM private.commit_action(
    p_game_id,
    p_user_id,
    NULL,  -- bot_id: forfeit is always a human action
    'system',
    v_action_data,
    v_new_state,
    v_new_pending,
    v_new_version,
    v_new_seed,
    v_current_player_times,
    v_config,
    v_schema_version,
    v_outcome,
    NULL,
    v_budget_seconds,
    v_turn_seconds,
    v_participant.player_index
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.forfeit_game(p_game_id UUID)
RETURNS VOID AS $$
BEGIN
  PERFORM private.do_forfeit_game(p_game_id, private.require_auth());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- INTERNAL: purge_user
-- Tears down a user's in-flight games then deletes their auth.users row
-- (cascading to public.users and SET-NULLing preserved game-history columns).
-- Shared by delete_account (caller deletes themselves) and
-- cleanup_stale_anonymous_users (cron deletes stale guests). Mirrors the
-- graceful teardown so games never end up with a null creator or ghost seat:
-- cancel created lobbies, leave joined lobbies, forfeit active games.
-- ============================================
CREATE OR REPLACE FUNCTION private.purge_user(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_game RECORD;
BEGIN
  -- Cancel all waiting/ready games this user created. Lock first so
  -- do_cancel_game's read sees a consistent row.
  FOR v_game IN
    SELECT id FROM public.games
    WHERE created_by = p_user_id AND status IN ('waiting', 'ready')
    FOR UPDATE
  LOOP
    PERFORM private.do_cancel_game(v_game.id, p_user_id);
  END LOOP;

  -- Leave all waiting/ready games this user joined but did not create.
  FOR v_game IN
    SELECT g.id FROM public.games g
    JOIN public.participants p ON p.game_id = g.id AND p.user_id = p_user_id
    WHERE g.status IN ('waiting', 'ready')
      AND g.created_by != p_user_id
    FOR UPDATE OF g
  LOOP
    PERFORM private.do_leave_game(v_game.id, p_user_id);
  END LOOP;

  -- Forfeit all active games so outcomes, observations, and rating triggers
  -- fire normally (do_forfeit_game takes its own FOR UPDATE lock).
  FOR v_game IN
    SELECT g.id FROM public.games g
    JOIN public.participants p ON p.game_id = g.id AND p.user_id = p_user_id
    WHERE g.status = 'active'
  LOOP
    PERFORM private.do_forfeit_game(v_game.id, p_user_id);
  END LOOP;

  DELETE FROM auth.users WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- RPC: submit_action
-- Validates action, applies it, fans out per-player observations.
-- ============================================
CREATE OR REPLACE FUNCTION public.submit_action(
  p_game_id          UUID,
  p_data             JSONB,
  p_expected_version INT
)
RETURNS VOID AS $$
DECLARE
  v_user_id              UUID;
  v_participant          RECORD;
  v_status               public.game_status;
  v_config               JSONB;
  v_turn_seconds         INT;
  v_budget_seconds       INT;
  v_increment_seconds    INT;
  v_action_seconds       INT;
  v_schema_version       INT;
  v_current_state        JSONB;
  v_current_pending      INT[];
  v_current_version      INT;
  v_current_seed         BIGINT;
  v_current_deadline     TIMESTAMPTZ;
  v_current_player_times BIGINT[];
  v_current_turn_started TIMESTAMPTZ;
  v_new_version          INT;
  v_new_seed             BIGINT;
  v_new_player_times     BIGINT[];
  v_result               JSONB;
  v_new_state            JSONB;
  v_new_pending          INT[];
  v_outcome              JSONB;
  v_elapsed_ms           BIGINT;
BEGIN
  v_user_id := private.require_auth();
  SELECT * INTO v_participant FROM private.require_participant(p_game_id, v_user_id);

  -- Acquire lock and check status atomically — no TOCTOU window between
  -- the active check and the lock. game_states is append-only so the games
  -- row serves as the serialization point for all concurrent writers.
  SELECT status, config, turn_seconds, budget_seconds, increment_seconds, schema_version
  INTO v_status, v_config, v_turn_seconds, v_budget_seconds, v_increment_seconds, v_schema_version
  FROM public.games WHERE id = p_game_id
  FOR UPDATE;

  IF v_status IS NULL THEN RAISE EXCEPTION 'Game not found'; END IF;
  IF v_status != 'active' THEN RAISE EXCEPTION 'Game is not active'; END IF;

  -- Read latest state — no FOR UPDATE needed, games row is already locked.
  SELECT state, pending_players, version, rng_seed, turn_deadline, player_times, turn_started_at
  INTO v_current_state, v_current_pending, v_current_version, v_current_seed,
       v_current_deadline, v_current_player_times, v_current_turn_started
  FROM public.game_states
  WHERE game_id = p_game_id
  ORDER BY version DESC
  LIMIT 1;

  -- Deadline check after lock: concurrent expire_turn may have already fired.
  IF v_current_deadline IS NOT NULL AND v_current_deadline < NOW() THEN
    RAISE EXCEPTION 'Turn has expired';
  END IF;

  -- Version check operates on the locked, consistent state.
  PERFORM private.validate_version(v_current_version, p_expected_version);

  IF NOT (v_participant.player_index = ANY(v_current_pending)) THEN
    RAISE EXCEPTION 'Not your turn';
  END IF;

  v_result      := private.game_apply_action(
    v_current_state, v_current_pending, p_data, v_participant.player_index, v_current_seed, v_config,
    v_schema_version
  );
  v_new_state   := v_result->'state';
  v_new_pending := ARRAY(SELECT jsonb_array_elements_text(v_result->'pending_players')::INT);
  v_outcome     := v_result->'outcome';
  v_new_seed    := (v_result->>'rng_seed')::BIGINT;
  IF v_new_seed IS NULL OR v_new_seed = 0 THEN
    RAISE EXCEPTION 'game_apply_action must return a non-zero rng_seed';
  END IF;
  v_new_version    := v_current_version + 1;
  v_action_seconds := (v_result->>'turn_seconds')::INT;

  -- Bank deduction: only when budget mode AND hook didn't override this action's timing.
  v_new_player_times := v_current_player_times;
  IF v_budget_seconds IS NOT NULL AND v_action_seconds IS NULL AND v_outcome IS NULL THEN
    IF v_current_turn_started IS NULL THEN
      RAISE EXCEPTION 'turn_started_at is NULL in budget game — this is a bug (game_id: %)', p_game_id;
    END IF;
    v_elapsed_ms := GREATEST(0,
      EXTRACT(EPOCH FROM (NOW() - v_current_turn_started)) * 1000
    )::BIGINT;
    -- Deduct elapsed from the acting player's bank, floor at 0.
    v_new_player_times[v_participant.player_index + 1] :=
      GREATEST(0, v_new_player_times[v_participant.player_index + 1] - v_elapsed_ms);
    -- Fischer increment added after each bank-consuming action.
    v_new_player_times[v_participant.player_index + 1] :=
      v_new_player_times[v_participant.player_index + 1]
      + (COALESCE(v_increment_seconds, 0) * 1000)::BIGINT;
  END IF;

  PERFORM private.commit_action(
    p_game_id,
    v_user_id,
    NULL,  -- bot_id: human submit_action always has a user_id
    'user',
    p_data,
    v_new_state,
    v_new_pending,
    v_new_version,
    v_new_seed,
    v_new_player_times,
    v_config,
    v_schema_version,
    v_outcome,
    v_action_seconds,
    v_budget_seconds,
    v_turn_seconds,
    v_participant.player_index
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- RPC: get_lobby_games
-- Returns public games open for joining: status waiting or ready, not yet full.
-- The full-game filter (participant count < max_players) is a HAVING clause on
-- a JOIN aggregate — PostgREST cannot express this as a WHERE filter on an
-- embedded resource count, so it lives here instead.
-- Ordered by created_at DESC for cursor-based pagination.
-- Returns participant details (user_id + player_index) per game so the client
-- can resolve player identities via the cached playerInfoProvider without
-- extra queries.
-- ============================================
CREATE OR REPLACE FUNCTION public.get_lobby_games(
  p_cursor TIMESTAMPTZ DEFAULT NULL,
  p_limit  INT         DEFAULT 50
)
RETURNS TABLE(
  id                UUID,
  created_by        UUID,
  status            public.game_status,
  access            public.game_access,
  turn_seconds      INT,
  budget_seconds    INT,
  increment_seconds INT,
  min_players       INT,
  max_players       INT,
  config            JSONB,
  schema_version    INT,
  rated             BOOLEAN,
  rating_pool       TEXT,
  created_at        TIMESTAMPTZ,
  finished_at       TIMESTAMPTZ,
  updated_at        TIMESTAMPTZ,
  participants      JSONB,
  is_participant    BOOLEAN
) AS $$
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
  WHERE g.access = 'public'
    AND g.status IN ('waiting', 'ready')
    AND (p_cursor IS NULL OR g.created_at < p_cursor)
  GROUP BY g.id
  HAVING COUNT(p.id) < g.max_players
  ORDER BY g.created_at DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '';

-- ============================================
-- INTERNAL: expire_all_turns
-- Called by pg_cron every minute. Finds all games with an expired deadline
-- and calls expire_turn for each one in an isolated subtransaction so that
-- a hook exception in one game never prevents the others from being processed.
-- ============================================
CREATE OR REPLACE FUNCTION private.expire_all_turns()
RETURNS VOID AS $$
DECLARE
  v_game_id UUID;
BEGIN
  -- DISTINCT ON filters to the latest version per game before checking the
  -- deadline, so historical rows with old deadlines are not matched.
  FOR v_game_id IN
    SELECT latest.game_id
    FROM (
      SELECT DISTINCT ON (gs.game_id) gs.game_id, gs.turn_deadline
      FROM   public.game_states gs
      JOIN   public.games g ON g.id = gs.game_id
      WHERE  g.status = 'active'
      ORDER  BY gs.game_id, gs.version DESC
    ) latest
    WHERE latest.turn_deadline IS NOT NULL
      AND latest.turn_deadline < NOW()
  LOOP
    BEGIN
      PERFORM private.expire_turn(v_game_id);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'expire_turn failed for game %: %', v_game_id, SQLERRM;
    END;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- INTERNAL: expire_turn
-- Called by pg_cron for games where turn_deadline < NOW().
-- Calls game_handle_system_action('timeout', …) once per pending player so
-- the game hook decides the consequence without mixing it into the player-
-- action path. New system event types follow the same pattern.
-- Runs as service role — no auth check needed.
-- ============================================
CREATE OR REPLACE FUNCTION private.expire_turn(p_game_id UUID)
RETURNS VOID AS $$
DECLARE
  v_config               JSONB;
  v_turn_seconds         INT;
  v_budget_seconds       INT;
  v_action_seconds       INT;
  v_schema_version       INT;
  v_current_state        JSONB;
  v_current_pending      INT[];
  v_current_version      INT;
  v_current_seed         BIGINT;
  v_current_deadline     TIMESTAMPTZ;
  v_current_player_times BIGINT[];
  v_new_version          INT;
  v_new_seed             BIGINT;
  v_new_player_times     BIGINT[];
  v_result               JSONB;
  v_new_state            JSONB;
  v_new_pending          INT[];
  v_outcome              JSONB;
  v_pending_player       INT;
  v_action_data          JSONB;
BEGIN
  -- FOR UPDATE on games serializes concurrent writers for this game.
  SELECT config, turn_seconds, budget_seconds, schema_version
  INTO v_config, v_turn_seconds, v_budget_seconds, v_schema_version
  FROM public.games WHERE id = p_game_id AND status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Read latest state — no FOR UPDATE needed, games row is already locked.
  SELECT state, pending_players, version, rng_seed, turn_deadline, player_times
  INTO v_current_state, v_current_pending, v_current_version, v_current_seed,
       v_current_deadline, v_current_player_times
  FROM public.game_states
  WHERE game_id = p_game_id
  ORDER BY version DESC
  LIMIT 1;

  -- Re-check under lock: a concurrent submit_action may have already acted.
  IF v_current_deadline IS NULL OR v_current_deadline >= NOW() THEN
    RETURN;
  END IF;

  -- Call game_handle_system_action for each pending player in order.
  -- Each call advances the state so later iterations see the updated state.
  -- FOREACH captures the array once; v_current_pending is reassigned inside,
  -- so we guard against players that a prior iteration already removed.
  FOREACH v_pending_player IN ARRAY v_current_pending LOOP
    IF NOT (v_pending_player = ANY(v_current_pending)) THEN
      CONTINUE;
    END IF;

    -- In budget mode, the timed-out player's bank drains to zero.
    -- No Fischer increment — the player did not successfully act.
    v_new_player_times := v_current_player_times;
    IF v_budget_seconds IS NOT NULL THEN
      v_new_player_times[v_pending_player + 1] := 0;
    END IF;

    v_action_data := jsonb_build_object('type', 'timeout', 'player_index', v_pending_player);

    v_result := private.game_handle_system_action(
      v_current_state,
      v_current_pending,
      'timeout'::public.system_action_type,
      v_action_data,
      v_current_seed,
      v_config,
      v_schema_version
    );

    v_new_state      := v_result->'state';
    v_new_pending    := ARRAY(SELECT jsonb_array_elements_text(v_result->'pending_players')::INT);
    v_outcome        := v_result->'outcome';
    v_new_seed       := (v_result->>'rng_seed')::BIGINT;
    IF v_new_seed IS NULL OR v_new_seed = 0 THEN
      RAISE EXCEPTION 'game_handle_system_action must return a non-zero rng_seed';
    END IF;
    v_new_version    := v_current_version + 1;
    v_action_seconds := (v_result->>'turn_seconds')::INT;

    PERFORM private.commit_action(
      p_game_id,
      NULL,  -- user_id: system action, no human actor
      NULL,  -- bot_id: system action, no bot actor
      'system',
      v_action_data,
      v_new_state,
      v_new_pending,
      v_new_version,
      v_new_seed,
      v_new_player_times,
      v_config,
      v_schema_version,
      v_outcome,
      v_action_seconds,
      v_budget_seconds,
      v_turn_seconds,
      v_pending_player  -- the timed-out player's seat index
    );

    IF v_outcome IS NOT NULL THEN
      RETURN;  -- game finished; stop processing remaining pending players
    END IF;

    -- Advance for next pending player iteration.
    v_current_state        := v_new_state;
    v_current_pending      := v_new_pending;
    v_current_version      := v_new_version;
    v_current_seed         := v_new_seed;
    v_current_player_times := v_new_player_times;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- INTERNAL: cleanup_idle_games
-- Called by pg_cron daily. Silently aborts abandoned games:
--   - waiting or ready games idle for > 7 days
--   - active untimed games with no action in the last 30 days
-- Timed games don't need this — clock expiry handles them via expire_turn.
-- No hook call, no outcomes written — just a status transition to 'aborted'.
-- ============================================
CREATE OR REPLACE FUNCTION private.cleanup_idle_games()
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

-- Delete stale anonymous (guest) accounts: anonymous, older than 90 days, with
-- no game action in the last 90 days. Each is torn down via private.purge_user
-- (cancel/leave/forfeit then delete) — the same path delete_account uses — so a
-- guest's lingering games are resolved gracefully rather than orphaned. Each
-- purge runs in its own subtransaction so one bad game can't block the rest.
CREATE OR REPLACE FUNCTION private.cleanup_stale_anonymous_users()
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
BEGIN
  FOR v_user_id IN
    SELECT au.id FROM auth.users au
    WHERE au.is_anonymous = true
      AND au.created_at < NOW() - INTERVAL '90 days'
      AND NOT EXISTS (
        SELECT 1 FROM public.actions a
        WHERE a.user_id = au.id
          AND a.created_at >= NOW() - INTERVAL '90 days'
      )
  LOOP
    BEGIN
      PERFORM private.purge_user(v_user_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Failed to purge stale anonymous user %: %', v_user_id, SQLERRM;
    END;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- RPC: get_replay
-- Returns the caller's observation slice at every historical state version.
-- Only available for finished games; caller must be a participant.
-- Projects each game_states row through game_compute_observation with
-- p_is_replay = TRUE — game hooks can use this to reveal post-game state
-- (e.g. opponent hole cards in Poker). Raw state is never exposed.
-- ============================================
CREATE OR REPLACE FUNCTION public.get_replay(p_game_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_status  public.game_status;
  v_config  JSONB;
  v_schema_version INT;
  v_part    RECORD;
  v_count   INT;
  v_result  JSONB := '[]'::JSONB;
  v_rec     RECORD;
  v_obs     JSONB;
BEGIN
  v_user_id := private.require_auth();

  SELECT status, config, schema_version INTO v_status, v_config, v_schema_version
  FROM public.games WHERE id = p_game_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Game not found';
  END IF;
  IF v_status != 'finished' THEN
    RAISE EXCEPTION 'Replay is only available for finished games';
  END IF;

  SELECT * INTO v_part FROM private.get_participant(p_game_id, v_user_id);
  IF v_part.participant_id IS NULL THEN
    RAISE EXCEPTION 'Not a participant in this game';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.participants WHERE game_id = p_game_id;

  FOR v_rec IN
    SELECT gs.version,
           gs.state,
           gs.pending_players,
           gs.created_at,
           a.type         AS action_type,
           a.data         AS action_data,
           a.player_index AS action_player_index
    FROM public.game_states gs
    LEFT JOIN public.actions a
           ON a.game_id = p_game_id AND a.version_after = gs.version
    WHERE gs.game_id = p_game_id
    ORDER BY gs.version
  LOOP
    v_obs := private.game_compute_observation(
      v_rec.state,
      v_rec.pending_players,
      v_part.player_index,
      v_count,
      v_config,
      v_schema_version,
      TRUE  -- p_is_replay: hooks may reveal post-game state
    );

    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'version',              v_rec.version,
      'data',                 v_obs->'data',
      'pending_players',      v_obs->'pending_players',
      'created_at',           v_rec.created_at,
      'action_type',          v_rec.action_type,
      'action_data',          v_rec.action_data,
      'action_player_index',  v_rec.action_player_index
    ));
  END LOOP;

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- Friends RPCs
-- ============================================

CREATE OR REPLACE FUNCTION public.send_friend_request(p_target_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
  v_u1 UUID;
  v_u2 UUID;
BEGIN
  v_user_id := private.require_auth();
  PERFORM private.require_permanent_user();
  IF v_user_id = p_target_user_id THEN
    RAISE EXCEPTION 'Cannot send friend request to yourself';
  END IF;
  
  v_u1 := LEAST(v_user_id, p_target_user_id);
  v_u2 := GREATEST(v_user_id, p_target_user_id);
  
  -- If there is a pending request from the target user, sending a request back should accept it.
  IF EXISTS (
    SELECT 1 FROM public.relationships
    WHERE user_id_1 = v_u1 AND user_id_2 = v_u2
      AND status = 'pending'
      AND initiated_by = p_target_user_id
  ) THEN
    PERFORM public.accept_friend_request(p_target_user_id);
    RETURN;
  END IF;

  INSERT INTO public.relationships (user_id_1, user_id_2, initiated_by, status)
  VALUES (v_u1, v_u2, v_user_id, 'pending')
  ON CONFLICT (user_id_1, user_id_2) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.accept_friend_request(p_target_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
  v_u1 UUID;
  v_u2 UUID;
BEGIN
  v_user_id := private.require_auth();
  PERFORM private.require_permanent_user();
  v_u1 := LEAST(v_user_id, p_target_user_id);
  v_u2 := GREATEST(v_user_id, p_target_user_id);

  UPDATE public.relationships
  SET status = 'accepted', updated_at = NOW()
  WHERE user_id_1 = v_u1 AND user_id_2 = v_u2 AND status = 'pending' AND initiated_by = p_target_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.remove_friend(p_target_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
  v_u1 UUID;
  v_u2 UUID;
BEGIN
  v_user_id := private.require_auth();
  PERFORM private.require_permanent_user();
  v_u1 := LEAST(v_user_id, p_target_user_id);
  v_u2 := GREATEST(v_user_id, p_target_user_id);

  DELETE FROM public.relationships
  WHERE user_id_1 = v_u1 AND user_id_2 = v_u2;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.search_users(p_query TEXT)
RETURNS TABLE (
  id           UUID,
  username     TEXT,
  display_name TEXT,
  avatar_url   TEXT
) AS $$
DECLARE
  v_pattern TEXT;
BEGIN
  PERFORM private.require_auth();
  PERFORM private.require_permanent_user();
  -- Strip % (the only ILIKE wildcard that causes unbounded matching).
  -- Display names have no character restriction so we must not strip Unicode.
  -- _ is kept: it's valid in usernames and its single-char wildcard is harmless.
  v_pattern := '%' || replace(p_query, '%', '') || '%';
  RETURN QUERY
  SELECT u.id, u.username, up.display_name, up.avatar_url
  FROM public.users u
  JOIN public.user_profiles up ON up.id = u.id
  WHERE u.username    ILIKE v_pattern
     OR up.display_name ILIKE v_pattern
  -- Best trigram match first, so exact and near-exact names beat
  -- incidental substring hits.
  ORDER BY GREATEST(
    extensions.similarity(u.username, p_query),
    extensions.similarity(COALESCE(up.display_name, ''), p_query)
  ) DESC
  LIMIT 20;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

-- ============================================
-- Game joining / discovery extensions
-- ============================================

CREATE OR REPLACE FUNCTION public.join_game_by_code(
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
    RAISE EXCEPTION 'Game not found';
  END IF;

  -- Delegate to standard join_game, forwarding the schema gate so a by-code or
  -- deep-link join is rejected before seating just like a lobby join.
  RETURN public.join_game(v_game_id, p_client_schema_version);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.get_friends_games(
  p_cursor TIMESTAMPTZ DEFAULT NULL,
  p_limit  INT         DEFAULT 50
)
RETURNS TABLE(
  id                UUID,
  created_by        UUID,
  status            public.game_status,
  access            public.game_access,
  turn_seconds      INT,
  budget_seconds    INT,
  increment_seconds INT,
  min_players       INT,
  max_players       INT,
  config            JSONB,
  schema_version    INT,
  rated             BOOLEAN,
  rating_pool       TEXT,
  created_at        TIMESTAMPTZ,
  finished_at       TIMESTAMPTZ,
  updated_at        TIMESTAMPTZ,
  participants      JSONB,
  is_participant    BOOLEAN
) AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := private.require_auth();
  RETURN QUERY
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
      WHERE pp.game_id = g.id AND pp.user_id = v_user_id
    ) AS is_participant
  FROM public.games g
  LEFT JOIN public.participants p ON p.game_id = g.id
  WHERE g.access = 'friends'
    AND g.status IN ('waiting', 'ready')
    AND (p_cursor IS NULL OR g.created_at < p_cursor)
    -- Caller's own rooms are included (you are not "friends with yourself",
    -- so the relationship check alone would hide them from their creator).
    AND (
      g.created_by = v_user_id
      OR EXISTS (
        -- Caller is friends with the creator
        SELECT 1 FROM public.relationships r
        WHERE ((r.user_id_1 = g.created_by AND r.user_id_2 = v_user_id)
           OR (r.user_id_2 = g.created_by AND r.user_id_1 = v_user_id))
          AND r.status = 'accepted'
      )
    )
  GROUP BY g.id
  HAVING COUNT(p.id) < g.max_players
  ORDER BY g.created_at DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

-- ============================================
-- ACCESS CONTROL
-- ============================================
-- Revoke from PUBLIC and anon, then re-grant to authenticated.
-- Revoking from PUBLIC covers the case where the default grant was to PUBLIC;
-- the explicit GRANT TO authenticated restores access for signed-in users.
-- ============================================
REVOKE EXECUTE ON FUNCTION public.create_game(integer, integer, integer, public.game_access, integer, integer, integer, jsonb, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_game(integer, integer, integer, public.game_access, integer, integer, integer, jsonb, boolean) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.join_game(uuid, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.join_game(uuid, integer) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.start_game(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.start_game(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.trigger_turn_expiry(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.trigger_turn_expiry(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.cancel_game(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.cancel_game(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.leave_game(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.leave_game(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.forfeit_game(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.forfeit_game(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.submit_action(uuid, jsonb, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.submit_action(uuid, jsonb, integer) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_replay(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_replay(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_lobby_games(timestamptz, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_lobby_games(timestamptz, integer) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_friends_games(timestamptz, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_friends_games(timestamptz, integer) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.send_friend_request(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.send_friend_request(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.accept_friend_request(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.accept_friend_request(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.remove_friend(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.remove_friend(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.search_users(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.search_users(text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.join_game_by_code(varchar, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.join_game_by_code(varchar, integer) TO authenticated;
