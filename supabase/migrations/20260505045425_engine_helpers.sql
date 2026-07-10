-- ============================================
-- Engine internals — shared SQL helpers & private cores
-- ============================================
-- Private utilities, the commit-transition helpers, and the parameterized
-- cores shared by a public wrapper and an internal caller. Depended on by every
-- later engine_/app_ migration.
--
-- Naming: engine_* = service-role, EF-only gated RPCs (REVOKEd from
-- authenticated). cron_* = pg_cron-scheduled private jobs. app_* =
-- client-direct RPCs (PostgREST, under RLS/auth). do_*/other private.* =
-- internal helpers. See docs/engine_architecture.md.
-- ============================================

CREATE OR REPLACE FUNCTION private.require_auth()
RETURNS UUID AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'EIG15';
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
    RAISE EXCEPTION 'Not a participant in this game' USING ERRCODE = 'EIG07';
  END IF;
  RETURN QUERY SELECT v_result.participant_id, v_result.player_index;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

-- Grace window (milliseconds) added to every deadline comparison so a player
-- who submits on time is not rejected because network latency carried the
-- request past the deadline (server time is measured at request arrival, not
-- at the tap). MUST be applied symmetrically everywhere a deadline is compared
-- to NOW() — the engine_commit_action accept guard, the system_timeout re-check
-- under lock, and the cron_expire_turns cron — otherwise the timeout path races ahead and
-- times out the on-time player anyway. In budget mode the grace is fair: the
-- elapsed bank deduction still runs, so it only forgives acceptance, not time
-- charged. Keep it small relative to per-action turn_seconds windows.
CREATE OR REPLACE FUNCTION private.deadline_grace_ms()
RETURNS BIGINT AS $$
  SELECT 750::BIGINT;
$$ LANGUAGE sql IMMUTABLE;

-- TRUE once a turn deadline (plus the latency grace window) has genuinely
-- passed, measured against the injected p_now. Single source of the
-- deadline+grace comparison applied symmetrically by the three places a
-- deadline is tested: the engine_commit_action accept guard, the system_timeout
-- abstain check, and the cron_expire_turns sweep — so the grace window can never
-- drift between them. A NULL deadline (untimed turn) is never expired.
CREATE OR REPLACE FUNCTION private.deadline_expired(
  p_deadline TIMESTAMPTZ,
  p_now      TIMESTAMPTZ
)
RETURNS BOOLEAN AS $$
  SELECT p_deadline IS NOT NULL
     AND p_deadline + private.deadline_grace_ms() * INTERVAL '1 millisecond' < p_now;
$$ LANGUAGE sql IMMUTABLE SET search_path = '';

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Writes game_outcomes rows and marks the game finished.
-- Owns the outcome → game_outcomes → games.status pipeline so it is
-- never duplicated across the engine_commit_action modes (move/forfeit/timeout).
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
    RAISE EXCEPTION 'applyAction returned non-array outcome';
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

-- ============================================
-- TIMING HELPERS
-- ============================================
-- Pure timing math. Both functions take the commit instant as an injected
-- p_now argument (sampled once per commit by the caller) rather than reading
-- NOW() themselves, so a single transaction's elapsed-deduction and next-deadline
-- resolve against the exact same instant. Being argument-pure they are IMMUTABLE,
-- touch no tables, and need no SECURITY DEFINER — they are unit-testable in psql.

-- Deducts the acting player's elapsed thinking time from their budget bank and
-- applies the Fischer increment. Returns the updated player_times array.
-- Floored at 0: a player who overran their bank lands at 0, not negative.
CREATE OR REPLACE FUNCTION private.deduct_bank(
  p_times         BIGINT[],
  p_index         INT,
  p_now           TIMESTAMPTZ,
  p_turn_started  TIMESTAMPTZ,
  p_increment_sec INT
)
RETURNS BIGINT[] AS $$
DECLARE
  v_times      BIGINT[] := p_times;
  v_elapsed_ms BIGINT;
BEGIN
  IF p_turn_started IS NULL THEN
    RAISE EXCEPTION 'deduct_bank called with NULL turn_started_at';
  END IF;
  v_elapsed_ms := GREATEST(0, EXTRACT(EPOCH FROM (p_now - p_turn_started)) * 1000)::BIGINT;
  v_times[p_index + 1] := GREATEST(0, v_times[p_index + 1] - v_elapsed_ms)
                          + (COALESCE(p_increment_sec, 0) * 1000)::BIGINT;
  RETURN v_times;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Computes the deadline and turn_started_at for the next action.
-- Centralises the precedence chain used by engine_commit_start and every
-- engine_commit_action mode. Pass p_outcome = NULL when no game-over has occurred.
CREATE OR REPLACE FUNCTION private.compute_next_deadline(
  p_now              TIMESTAMPTZ,
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
      OR p_turn_seconds   IS NOT NULL THEN p_now
    ELSE NULL
  END;

  deadline := CASE
    WHEN p_outcome IS NOT NULL THEN NULL
    WHEN p_action_seconds IS NOT NULL
      THEN p_now + (p_action_seconds * interval '1 second')
    -- Use the minimum remaining budget across all pending players so the
    -- deadline fires as soon as the first player's clock runs out.
    -- NOTE: budget mode allows at most one pending seat (sequential games) —
    -- enforced at the source by the EF's assertBudgetPending, which 500s any
    -- hook envelope that violates it before commit (no CHECK here: pending
    -- lives on game_states, budget on games). This MIN remains the
    -- graceful-degradation safeguard should a multi-pending state ever reach
    -- SQL anyway; the system_timeout commit still drains all pending players'
    -- banks when it fires, not just the first.
    WHEN p_budget_seconds IS NOT NULL AND cardinality(p_new_pending) > 0
      THEN p_now + (
        (SELECT MIN(p_new_player_times[idx + 1])
         FROM unnest(p_new_pending) AS idx)::NUMERIC / 1000 * interval '1 second'
      )
    WHEN p_turn_seconds IS NOT NULL
      THEN p_now + (p_turn_seconds * interval '1 second')
    ELSE NULL
  END;

  RETURN NEXT;
END;
$$ LANGUAGE plpgsql IMMUTABLE SET search_path = '';

-- ============================================
-- ENGINE EDGE-FUNCTION BRIDGE
-- ============================================
-- The four heavy game hooks (initial_state, apply_action, apply_lifecycle,
-- compute_observation) run as a TypeScript gameModule inside the
-- `game` Edge Function. Postgres does not compute rules; it keeps the
-- lock, the optimistic version check, timing/bank math, persistence and the
-- hidden-info fan-out behind these **service-role-only** RPCs. The EF reads
-- ground-truth state, runs the gameModule + projects observations, then commits.
-- See docs/game_logic_serverless_migration.md.
--
-- Trust boundary: every engine_* RPC here is REVOKEd from PUBLIC/anon/authenticated
-- (mirroring apply_rating_updates) — only the EF (service role) may call them.
-- Clients submit *intents* to the EF; only the EF submits *computed states*.
-- ============================================

-- Appends EF-computed observation slices as new per-seat rows at p_version
-- (observations are append-only history, one row per seat per version),
-- stamping the infra-owned version + timing columns (the slice
-- `data`/`pending_players` come from the EF) and joining each seat's identity
-- from participants, mirroring engine_commit_start's v0 insert.
CREATE OR REPLACE FUNCTION private.write_observation_slices(
  p_game_id         UUID,
  p_observations    JSONB,
  p_version         INT,
  p_deadline        TIMESTAMPTZ,
  p_player_times    BIGINT[],
  p_turn_started_at TIMESTAMPTZ
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO public.observations
    (game_id, user_id, bot_id, player_index, data, pending_players, version,
     turn_deadline, player_times, turn_started_at)
  SELECT p_game_id, part.user_id, part.bot_id, (e->>'player_index')::INT,
         e->'data',
         ARRAY(SELECT jsonb_array_elements_text(e->'pending_players')::INT),
         p_version, p_deadline, p_player_times, p_turn_started_at
  FROM jsonb_array_elements(p_observations) e
  JOIN public.participants part
    ON part.game_id = p_game_id AND part.player_index = (e->>'player_index')::INT
  -- No viewer, no slice: a seat purged mid-game (post-forfeit account
  -- deletion) has neither identity. Observations are keyed to their viewer
  -- (RLS + realtime filter by identity), so a row here would be unreadable
  -- forever — and would violate observation_identity_xor.
  WHERE part.user_id IS NOT NULL OR part.bot_id IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Shared precondition policy for engine_commit_action. Centralises the
-- "timeout abstains, every other mode hard-fails" rule that the status
-- and optimistic-version guards both apply, so it lives in one place instead of
-- being duplicated per guard. Returns TRUE when a timeout commit lost the
-- race (game no longer active, or the version moved) and the caller should
-- RETURN without acting; RAISES for a real error (missing game — never abstained —
-- non-active or stale state in a user/bot/forfeit commit).
--
-- NOTE: p_mode is the raw mode string engine_commit_action receives, so the
-- abstain branch must match 'timeout' — the value the EF actually sends
-- (game-routes.ts → commitAction). Keep this literal in sync with that mode.
CREATE OR REPLACE FUNCTION private.commit_should_abstain(
  p_mode             TEXT,
  p_status           public.game_status,
  p_cur_version      INT,
  p_expected_version INT
)
RETURNS BOOLEAN AS $$
BEGIN
  IF p_status IS NULL THEN
    RAISE EXCEPTION 'Game not found' USING ERRCODE = 'EIG06';
  END IF;
  IF p_status != 'active' THEN
    IF p_mode = 'timeout' THEN RETURN TRUE; END IF;
    RAISE EXCEPTION 'Game is not active' USING ERRCODE = 'EIG05';
  END IF;
  -- Every mode sends the version it computed against; a NULL would silently
  -- skip the optimistic guard, so it is a caller bug and raises.
  IF p_expected_version IS NULL THEN
    RAISE EXCEPTION 'p_expected_version is required';
  END IF;
  IF p_cur_version != p_expected_version THEN
    IF p_mode = 'timeout' THEN RETURN TRUE; END IF;
    -- Board advanced. SQLSTATE EIG02 lets the EF classify this for retry by code
    -- (a forfeit recomputes against the new state; a user/bot move rejects it).
    RAISE EXCEPTION 'Stale state: expected version %, current %',
      p_expected_version, p_cur_version
      USING ERRCODE = 'EIG02';
  END IF;
  RETURN FALSE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Persists ONE EF-computed transition: append game_states + actions, finish_game
-- on outcome, write observation slices. Bank/timing for the row are passed in
-- (the caller owns bank deduction); the deadline is derived here. `p_rng_seed`
-- is the game's base seed, copied verbatim from the previous row by the caller
-- (the EF derives per-transition randomness from it; it never crosses the
-- commit wire). Shared by every engine_commit_action mode and reused per-step
-- by the batched timeout path.
CREATE OR REPLACE FUNCTION private.persist_transition(
  p_now            TIMESTAMPTZ,
  p_game_id        UUID,
  p_action_type    public.action_type,
  p_action_kind    public.action_kind,
  p_acting_user_id UUID,
  p_acting_bot_id  UUID,
  p_transition     JSONB,
  p_new_version    INT,
  p_rng_seed       TEXT,
  p_budget_seconds INT,
  p_turn_seconds   INT,
  p_player_times   BIGINT[]
)
RETURNS VOID AS $$
DECLARE
  v_state          JSONB := p_transition->'new_state';
  v_pending        INT[] := ARRAY(SELECT jsonb_array_elements_text(p_transition->'new_pending')::INT);
  v_outcome        JSONB := p_transition->'outcome';
  v_action_seconds INT   := (p_transition->>'turn_seconds')::INT;
  v_player_index   INT   := (p_transition->>'player_index')::INT;
  v_action_data    JSONB := p_transition->'action_data';
  v_obs            JSONB := p_transition->'observations';
  v_rating_updates JSONB := p_transition->'rating_updates';
  v_rated          BOOLEAN;
  v_rating_pool    TEXT;
  v_dl             RECORD;
BEGIN
  -- The EF sends JSON null (not absent) for an ongoing move; normalise to SQL NULL.
  IF v_outcome IS NOT NULL AND jsonb_typeof(v_outcome) = 'null' THEN
    v_outcome := NULL;
  END IF;

  SELECT * INTO v_dl FROM private.compute_next_deadline(
    p_now, v_outcome, v_action_seconds, p_budget_seconds, p_turn_seconds, v_pending, p_player_times
  );

  INSERT INTO public.game_states
    (game_id, version, state, pending_players, rng_seed,
     turn_deadline, player_times, turn_started_at)
  VALUES
    (p_game_id, p_new_version, v_state, v_pending, p_rng_seed,
     v_dl.deadline, p_player_times, v_dl.turn_started_at);

  -- Identity = who performed the action; kind = which species it is. For
  -- system actions (timeout/engine forfeit) the caller passes NULL
  -- user_id/bot_id and the transition omits player_index, so all three land
  -- NULL (enforced by actions_identity_check).
  INSERT INTO public.actions (game_id, user_id, bot_id, type, kind, data, player_index, version_after)
  VALUES (p_game_id, p_acting_user_id, p_acting_bot_id, p_action_type,
          p_action_kind, v_action_data, v_player_index, p_new_version);

  -- finish_game before observations so the games realtime event precedes the
  -- observations event.
  -- On a rated finish, write the EF-computed OpenSkill updates in the SAME
  -- transaction, so ratings land atomically with the result. The
  -- rating_history unique (game, identity) index still guards double-apply.
  IF v_outcome IS NOT NULL THEN
    PERFORM private.finish_game(p_game_id, v_outcome);

    IF v_rating_updates IS NOT NULL
       AND jsonb_typeof(v_rating_updates) = 'array'
       AND jsonb_array_length(v_rating_updates) > 0 THEN
      SELECT rated, rating_pool INTO v_rated, v_rating_pool
      FROM public.games WHERE id = p_game_id;
      IF v_rated AND v_rating_pool IS NOT NULL THEN
        PERFORM private.apply_rating_updates(p_game_id, v_rating_pool, v_rating_updates);
      END IF;
    END IF;
  END IF;

  PERFORM private.write_observation_slices(
    p_game_id, v_obs, p_new_version, v_dl.deadline, p_player_times, v_dl.turn_started_at
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- (Former seatable_bot_ids RPC removed.) The bot pickers now filter the cached
-- app_bots catalog locally via GameModule.botSeatable, and the EF enforces the
-- same rule (GameRules.botSeatable) before seating — no DB round-trip per config.

-- Participants are read directly from the participants table (RLS-gated by game
-- visibility) — they are ephemeral, per-game data. A bot seat's static reference
-- data (username for the localBots match, local config for chooseAction) is NOT
-- joined here: identity resolves via app_players/playerInfoCache and capability via
-- the cached app_bots catalog, each keyed by the participant's id. So there is no
-- get_participants RPC.

-- ============================================
-- RPC: app_cancel_game
-- Aborts a waiting or ready game (creator only).
-- ============================================
-- Core cancel logic, parameterised by the acting user. Shared by the public
-- app_cancel_game RPC (caller = auth.uid()) and private.purge_user (acting on
-- another user during account deletion / stale-guest cleanup).
CREATE OR REPLACE FUNCTION private.do_cancel_game(p_game_id UUID, p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_created_by UUID;
  v_status     public.game_status;
BEGIN
  -- Lock the game row so the status check and the abort UPDATE are atomic against
  -- a concurrent engine_commit_start. Without the lock, cancel can read 'ready',
  -- start can then flip the game to 'active' (writing game_states v0), and cancel's
  -- predicate-less UPDATE would abort the now-active game out from under the
  -- players. Mirrors the FOR UPDATE in do_leave_game and engine_commit_start.
  SELECT created_by, status INTO v_created_by, v_status
  FROM public.games WHERE id = p_game_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Game not found' USING ERRCODE = 'EIG06';
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

-- ============================================
-- RPC: app_leave_game
-- Non-creator participant leaves a waiting or ready game.
-- Compacts player_index values so no gaps exist for the next joiner.
-- Transitions ready → waiting if the count drops below min_players.
-- The creator cannot leave — use app_cancel_game instead.
-- ============================================
-- Core leave logic, parameterised by the acting user. Shared by the public
-- app_leave_game RPC and private.purge_user.
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
    RAISE EXCEPTION 'Game not found' USING ERRCODE = 'EIG06';
  END IF;
  IF v_created_by = p_user_id THEN
    RAISE EXCEPTION 'Creator cannot leave — use app_cancel_game instead';
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

-- Shared security boundary for the two client-facing local-bot RPCs (observation
-- read + action submit): asserts p_caller is the SOLE human of a solo game and that
-- p_player_index is a *local* bot seat in it, returning that seat's bot_id. Defining
-- it once keeps the gate from drifting between the two entry points. STABLE: pure
-- reads; the callers that mutate take the games lock in apply_seat_action.
CREATE OR REPLACE FUNCTION private.resolve_local_bot_seat(
  p_game_id      UUID,
  p_player_index INT,
  p_caller       UUID
)
RETURNS UUID AS $$
DECLARE
  v_bot_id      UUID;
  v_is_local    BOOLEAN;
  v_human_count INT;
BEGIN
  IF NOT private.is_game_participant(p_game_id, p_caller) THEN
    RAISE EXCEPTION 'Not a participant in this game' USING ERRCODE = 'EIG07';
  END IF;

  SELECT p.bot_id, b.is_local INTO v_bot_id, v_is_local
  FROM public.participants p
  JOIN public.bots b ON b.id = p.bot_id
  WHERE p.game_id = p_game_id AND p.player_index = p_player_index AND p.type = 'bot';

  IF v_bot_id IS NULL THEN
    RAISE EXCEPTION 'Seat % is not a bot in this game', p_player_index;
  END IF;
  -- Local bots only: a server bot acts solely through the bot/action route
  -- (HMAC-authenticated) and computes remotely, so a client neither drives nor reads it.
  -- Allowing it would let a participant front-run the opponent bot in a multi-human
  -- or rated game.
  IF NOT v_is_local THEN
    RAISE EXCEPTION 'Seat % is a server bot and cannot be driven by a client', p_player_index;
  END IF;

  -- Sole-human gate: the caller is a participating human, so exactly one human means
  -- the caller is alone — nobody to cheat against.
  SELECT COUNT(*) INTO v_human_count
  FROM public.participants
  WHERE game_id = p_game_id AND user_id IS NOT NULL;
  IF v_human_count <> 1 THEN
    RAISE EXCEPTION 'Local bot play is only available in a solo game';
  END IF;

  RETURN v_bot_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';
