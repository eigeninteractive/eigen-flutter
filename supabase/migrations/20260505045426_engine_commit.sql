-- ============================================
-- Engine commit & read RPCs (service-role, EF-only)
-- ============================================
-- The edge function's commit chokepoint and the ground-truth reads it runs the
-- TypeScript GameEngine against. All REVOKEd from authenticated.
--
-- Naming: engine_* = service-role, EF-only gated RPCs (REVOKEd from
-- authenticated). cron_* = pg_cron-scheduled private jobs. app_* =
-- client-direct RPCs (PostgREST, under RLS/auth). do_*/other private.* =
-- internal helpers. See docs/engine_architecture.md.
-- ============================================

-- Commits the start of a game from EF-computed initial state + observation
-- slices. Idempotent: a no-op if the game is already active (retry-safe). Writes
-- game_states v0 + one observation row per participant, flips status to active.
CREATE OR REPLACE FUNCTION public.engine_commit_start(
  p_caller_id      UUID,
  p_game_id        UUID,
  p_initial_state  JSONB,
  p_pending        JSONB,
  p_seed           TEXT,
  p_turn_seconds   INT,
  p_observations   JSONB
)
RETURNS VOID AS $$
DECLARE
  v_status       public.game_status;
  v_created_by   UUID;
  v_turn_seconds INT;
  v_budget       INT;
  v_count        INT;
  v_pending      INT[];
  v_seed         BIGINT;
  v_player_times BIGINT[];
  v_dl           RECORD;
  v_now          TIMESTAMPTZ := NOW();
BEGIN
  SELECT status, created_by, turn_seconds, budget_seconds
  INTO v_status, v_created_by, v_turn_seconds, v_budget
  FROM public.games WHERE id = p_game_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Game not found'; END IF;
  IF v_created_by IS NULL OR v_created_by != p_caller_id THEN
    RAISE EXCEPTION 'Only the game creator can start the game';
  END IF;
  IF v_status = 'active' THEN RETURN; END IF;  -- idempotent
  IF v_status != 'ready' THEN RAISE EXCEPTION 'Game is not ready to start'; END IF;

  v_seed := p_seed::BIGINT;
  IF v_seed IS NULL OR v_seed = 0 THEN
    RAISE EXCEPTION 'initial rng_seed must be non-zero';
  END IF;
  v_pending := ARRAY(SELECT jsonb_array_elements_text(p_pending)::INT);

  SELECT COUNT(*) INTO v_count FROM public.participants WHERE game_id = p_game_id;

  IF v_budget IS NOT NULL THEN
    v_player_times := array_fill((v_budget * 1000)::BIGINT, ARRAY[v_count]);
  END IF;

  SELECT * INTO v_dl FROM private.compute_next_deadline(
    v_now, NULL, p_turn_seconds, v_budget, v_turn_seconds, v_pending, v_player_times
  );

  INSERT INTO public.game_states
    (game_id, version, state, pending_players, rng_seed, turn_deadline, player_times, turn_started_at)
  VALUES
    (p_game_id, 0, p_initial_state, v_pending, v_seed,
     v_dl.deadline, v_player_times, v_dl.turn_started_at);

  -- One observation row per participant (human and bot), identity joined from
  -- participants; the EF supplied the per-seat data/pending slices.
  INSERT INTO public.observations
    (game_id, user_id, bot_id, player_index, data, pending_players, version,
     turn_deadline, player_times, turn_started_at)
  SELECT p_game_id, part.user_id, part.bot_id, (e->>'player_index')::INT,
         e->'data',
         ARRAY(SELECT jsonb_array_elements_text(e->'pending_players')::INT),
         0, v_dl.deadline, v_player_times, v_dl.turn_started_at
  FROM jsonb_array_elements(p_observations) e
  JOIN public.participants part
    ON part.game_id = p_game_id AND part.player_index = (e->>'player_index')::INT;

  UPDATE public.games SET status = 'active' WHERE id = p_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- (Server-bot HMAC verification lives in the edge function — see
-- _engine/bot_auth.ts. The per-bot key is derived from the BOT_SIGNING_SECRET
-- env secret as HMAC(master, bot_id); no key material lives in Vault and the EF
-- needs no round-trip to verify a bot action or sign a wake.)

-- Service-role only (mirrors apply_rating_updates): clients never call these.
REVOKE EXECUTE ON FUNCTION public.engine_commit_start(UUID, UUID, JSONB, JSONB, TEXT, INT, JSONB) FROM PUBLIC, anon, authenticated;

-- Commits one EF-computed action transition under the games lock.
-- Identity model: the action row records WHO performed it. user/bot/resign carry
-- an identity (+ seat); forfeit/timeout are identity-less system actions.
-- Modes:
--   user / bot — deadline+grace, optimistic version, and pending-seat checks;
--                bank deduction in budget mode. type = user / bot.
--   resign     — a user voluntarily forfeits; version check only (no
--                deadline/pending), bank untouched. type = user, carries the
--                resigning user_id + seat.
--   forfeit    — engine-driven forfeit (account deletion); version check only.
--                type = system, no identity. Bank untouched.
--   timeout    — re-checks expiry+grace under lock and ABSTAINS (no error) if a
--                real action already won the race or the version moved. One
--                identity-less system transition resolving the whole pending set
--                (the hook decides holistically); zeroes every pending seat's bank.
CREATE OR REPLACE FUNCTION public.engine_commit_action(
  p_mode             TEXT,
  p_game_id          UUID,
  p_caller_id        UUID,
  p_acting_bot_id    UUID,
  p_expected_version INT,
  p_transitions      JSONB
)
RETURNS VOID AS $$
DECLARE
  v_status            public.game_status;
  v_config            JSONB;
  v_turn_seconds      INT;
  v_budget            INT;
  v_increment         INT;
  v_schema            INT;
  v_cur_state         JSONB;
  v_cur_pending       INT[];
  v_cur_version       INT;
  v_cur_deadline      TIMESTAMPTZ;
  v_cur_player_times  BIGINT[];
  v_cur_turn_started  TIMESTAMPTZ;
  v_action_type       public.action_type;
  v_t                 JSONB;
  v_t_player_index    INT;
  v_t_action_seconds  INT;
  v_t_outcome         JSONB;
  v_new_player_times  BIGINT[];
  v_seat              INT;
  v_now               TIMESTAMPTZ := NOW();
BEGIN
  SELECT status, config, turn_seconds, budget_seconds, increment_seconds, schema_version
  INTO v_status, v_config, v_turn_seconds, v_budget, v_increment, v_schema
  FROM public.games WHERE id = p_game_id
  FOR UPDATE;

  SELECT state, pending_players, version, turn_deadline, player_times, turn_started_at
  INTO v_cur_state, v_cur_pending, v_cur_version, v_cur_deadline,
       v_cur_player_times, v_cur_turn_started
  FROM public.game_states
  WHERE game_id = p_game_id
  ORDER BY version DESC LIMIT 1;

  -- Precondition policy (shared by status + optimistic-version guards): a missing
  -- game always raises; a timeout that lost the race — game no longer
  -- active, or the EF computed from a now-stale version — abstains; every other
  -- mode hard-fails.
  IF private.commit_should_abstain(p_mode, v_status, v_cur_version, p_expected_version) THEN
    RETURN;
  END IF;

  v_action_type := CASE p_mode
    WHEN 'user'    THEN 'user'
    WHEN 'bot'     THEN 'bot'
    WHEN 'resign'  THEN 'user'    -- a user performed it
    WHEN 'forfeit' THEN 'system'  -- engine-driven (account deletion)
    WHEN 'timeout' THEN 'system'
    ELSE NULL
  END::public.action_type;
  IF v_action_type IS NULL THEN
    RAISE EXCEPTION 'Unknown commit mode: %', p_mode;
  END IF;

  v_t := p_transitions->0;

  -- ── Timeout ─────────────────────────────────────────────────────────────────
  -- One identity-less system action over the whole pending set. The seats all
  -- share the single deadline, so all of them timed out; the hook already
  -- resolved them holistically into this one transition.
  IF p_mode = 'timeout' THEN
    -- Deadline must genuinely be expired (grace symmetry with submit acceptance).
    IF NOT private.deadline_expired(v_cur_deadline, v_now) THEN
      RETURN;  -- a real action won the race, or it is not expired yet
    END IF;

    v_new_player_times := v_cur_player_times;
    IF v_budget IS NOT NULL AND v_cur_pending IS NOT NULL THEN
      FOREACH v_seat IN ARRAY v_cur_pending LOOP
        v_new_player_times[v_seat + 1] := 0;  -- every pending seat's bank drains
      END LOOP;
    END IF;

    PERFORM private.persist_transition(
      v_now, p_game_id, 'system', NULL, NULL, v_t,
      v_cur_version + 1, v_budget, v_turn_seconds, v_new_player_times
    );
    RETURN;
  END IF;

  -- ── User / bot move ─────────────────────────────────────────────────────────
  IF p_mode IN ('user', 'bot') THEN
    IF private.deadline_expired(v_cur_deadline, v_now) THEN
      RAISE EXCEPTION 'Turn has expired';
    END IF;
    v_t_player_index := (v_t->>'player_index')::INT;
    IF NOT (v_t_player_index = ANY(v_cur_pending)) THEN
      RAISE EXCEPTION 'Not your turn';
    END IF;

    v_new_player_times := v_cur_player_times;
    v_t_action_seconds := (v_t->>'turn_seconds')::INT;
    v_t_outcome        := v_t->'outcome';
    IF v_t_outcome IS NOT NULL AND jsonb_typeof(v_t_outcome) = 'null' THEN
      v_t_outcome := NULL;
    END IF;

    -- Bank deduction: budget mode, no per-action override, game not ending.
    IF v_budget IS NOT NULL AND v_t_action_seconds IS NULL AND v_t_outcome IS NULL THEN
      v_new_player_times := private.deduct_bank(
        v_new_player_times, v_t_player_index, v_now, v_cur_turn_started, v_increment
      );
    END IF;

    PERFORM private.persist_transition(
      v_now, p_game_id, v_action_type, p_caller_id, p_acting_bot_id, v_t,
      v_cur_version + 1, v_budget, v_turn_seconds, v_new_player_times
    );
    RETURN;
  END IF;

  -- ── Resign / forfeit ────────────────────────────────────────────────────────
  -- Unconditional intent (no deadline/pending guard), bank untouched. resign is a
  -- user action carrying the resigning user's id + seat; forfeit is an
  -- identity-less system action. They share this path and differ only by
  -- v_action_type (set above) and the acting identity below.
  PERFORM private.persist_transition(
    v_now, p_game_id, v_action_type,
    CASE WHEN p_mode = 'resign' THEN p_caller_id ELSE NULL END,
    NULL, v_t, v_cur_version + 1, v_budget, v_turn_seconds, v_cur_player_times
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.engine_commit_action(TEXT, UUID, UUID, UUID, INT, JSONB) FROM PUBLIC, anon, authenticated;

