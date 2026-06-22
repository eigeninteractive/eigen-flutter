-- pg_net is required for net.http_post used throughout this file.
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- pgcrypto provides extensions.hmac(), used to sign server-bot wakes (below).
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- FCM push notification triggers.
--
-- Three triggers fire push notifications:
--   observations INSERT/UPDATE → your_turn      (this user's index entered pending_players;
--                                                INSERT covers start_game's version-0 rows)
--   games        INSERT        → game_invite    (friends-access game created)
--   relationships INSERT       → friend_request (pending relationship inserted)
--
-- FCM is sent directly via net.http_post using a cached OAuth token stored in
-- private.app_config (key = 'fcm_access_token'). The token is refreshed every
-- 50 minutes by the refresh-fcm-token edge function, called by the cron job
-- at the bottom of this file. All sends are fire-and-forget.
--
-- If FCM is not configured (app_config rows absent), every send is a no-op
-- with a WARNING — notifications degrade gracefully in local dev.

-- ── store_fcm_access_token ────────────────────────────────────────────────────
-- Called by the refresh-fcm-token edge function (service role only).
-- Caches the Google OAuth token and project ID so triggers can send FCM
-- calls directly without touching Google's OAuth endpoint per-notification.

CREATE OR REPLACE FUNCTION public.store_fcm_access_token(
  p_token      text,
  p_project_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO private.app_config (key, value)
  VALUES ('fcm_access_token', p_token)
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_at = now();

  INSERT INTO private.app_config (key, value)
  VALUES ('firebase_project_id', p_project_id)
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_at = now();
END;
$$;

-- Only the service_role (used by the edge function) may call this.
-- anon and authenticated roles must not be able to forge token writes.
REVOKE EXECUTE ON FUNCTION public.store_fcm_access_token(text, text)
  FROM PUBLIC, anon, authenticated;

-- ── send_push_notification ────────────────────────────────────────────────────
-- Core helper: sends one FCM message per device token registered for a user.
-- Reads the cached OAuth token and project ID from private.app_config.
-- Returns immediately if FCM is not configured (graceful degradation).

CREATE OR REPLACE FUNCTION private.send_push_notification(
  p_user_id uuid,
  p_title   text,
  p_body    text,
  p_data    jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_access_token text;
  v_project_id   text;
  v_fcm_url      text;
  r              record;
BEGIN
  SELECT value INTO v_access_token
  FROM private.app_config WHERE key = 'fcm_access_token';

  SELECT value INTO v_project_id
  FROM private.app_config WHERE key = 'firebase_project_id';

  IF v_access_token IS NULL OR v_project_id IS NULL THEN
    RAISE WARNING 'Push notification skipped for %: FCM not configured', p_user_id;
    RETURN;
  END IF;

  v_fcm_url :=
    'https://fcm.googleapis.com/v1/projects/' || v_project_id || '/messages:send';

  FOR r IN
    SELECT token FROM public.device_tokens WHERE user_id = p_user_id
  LOOP
    PERFORM net.http_post(
      url     := v_fcm_url,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_access_token,
        'Content-Type',  'application/json'
      ),
      body    := jsonb_build_object(
        'message', jsonb_build_object(
          'token',        r.token,
          'notification', jsonb_build_object('title', p_title, 'body', p_body),
          'data',         p_data
        )
      )
    );
  END LOOP;
END;
$$;

-- ── send_bot_wake ───────────────────────────────────────────────────────────
-- Wakes a *server* bot when it is its turn, carrying the observation so the bot
-- needs no callback to fetch state (wake-with-observation). No-op for a local
-- bot (is_local) — those are driven by the sole human's client.
--
-- The wake is authenticated with a *per-bot* HMAC: the body is signed with that
-- bot's own symmetric secret. The bot recomputes base64 HMAC-SHA256 over the exact
-- JSON body bytes (sent in x-wake-signature) and compares.
--
-- The same per-bot secret authenticates the bot's *action* the other way
-- (submit_bot_action_signed). Sharing one secret needs no domain-separation prefix:
-- this wake carries an observation and no move, an action carries a move and no
-- observation, so a captured MAC reflected into the other direction has nothing to
-- act on.
--
-- The secret lives in Vault under the per-bot name 'bot_secret_<bot_id>', set by
-- the operator at insert time. Fire-and-forget via pg_net.

CREATE OR REPLACE FUNCTION private.send_bot_wake(
  p_bot_id          uuid,
  p_game_id         uuid,
  p_player_index    int,
  p_data            jsonb,
  p_version         int,
  p_pending_players int[],
  p_turn_deadline   timestamptz
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_is_local    boolean;
  v_webhook_url text;
  v_username    text;
  v_config      jsonb;
  v_secret      text;
  v_body        jsonb;
  v_signature   text;
BEGIN
  SELECT is_local, webhook_url, username, config
    INTO v_is_local, v_webhook_url, v_username, v_config
  FROM public.bots WHERE id = p_bot_id;
  IF v_is_local THEN
    RETURN;  -- local bot: driven by the client, never woken
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'bot_secret_' || p_bot_id;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'Bot wake skipped for %: bot_secret_% not in Vault',
      p_bot_id, p_bot_id;
    RETURN;
  END IF;

  -- Build the body once, then HMAC its canonical text form. pg_net serialises
  -- the same jsonb to the same bytes, so the signature covers exactly what is
  -- sent and the bot can verify over the raw request body without re-serialising.
  v_body := jsonb_build_object(
    'game_id',         p_game_id,
    'bot_id',          p_bot_id,
    'player_index',    p_player_index,
    'username',        v_username,
    'config',          v_config,
    'observation',     p_data,
    'version',         p_version,
    'pending_players', p_pending_players,
    'turn_deadline',   p_turn_deadline
  );

  v_signature := encode(
    extensions.hmac(v_body::text, v_secret, 'sha256'),
    'base64'
  );

  PERFORM net.http_post(
    url     := v_webhook_url,
    headers := jsonb_build_object(
      'Content-Type',     'application/json',
      'x-wake-signature', v_signature
    ),
    body    := v_body
  );
END;
$$;

-- ── notify_your_turn ──────────────────────────────────────────────────────────
-- Fires when a seat's player_index enters pending_players (it's now its turn).
-- Covers INSERT (start_game's version-0 rows — the game's first move) and UPDATE
-- (every subsequent fan-out). One row exists per participant, so this also drives
-- bots: a human row sends an FCM push, a bot row sends a server-bot wake.

CREATE OR REPLACE FUNCTION private.notify_your_turn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.pending_players = OLD.pending_players THEN
    RETURN NEW;
  END IF;

  -- This seat must be pending now (player_index is on the row itself).
  IF NOT (NEW.player_index = ANY(NEW.pending_players)) THEN
    RETURN NEW;
  END IF;

  -- On UPDATE, only fire when the index *newly* entered the pending set.
  -- On INSERT there is no previous set — pending at version 0 means fire.
  IF TG_OP = 'UPDATE' AND NEW.player_index = ANY(OLD.pending_players) THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS NOT NULL THEN
    PERFORM private.send_push_notification(
      p_user_id => NEW.user_id,
      p_title   => 'Your turn',
      p_body    => 'It''s your move.',
      p_data    => jsonb_build_object(
        'category',  'your_turn',
        'deep_link', '/game/' || NEW.game_id
      )
    );
  ELSIF NEW.bot_id IS NOT NULL THEN
    PERFORM private.send_bot_wake(
      NEW.bot_id, NEW.game_id, NEW.player_index, NEW.data, NEW.version,
      NEW.pending_players, NEW.turn_deadline
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_observation_changed_notify_your_turn
  AFTER INSERT OR UPDATE ON public.observations
  FOR EACH ROW EXECUTE FUNCTION private.notify_your_turn();

-- ── notify_game_invite ────────────────────────────────────────────────────────
-- Fires after a friends-access game is created and notifies all accepted
-- friends of the creator so they can join.

CREATE OR REPLACE FUNCTION private.notify_game_invite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_display_name text;
  r              record;
BEGIN
  -- Only friends-access games push — they are a deliberate "play with
  -- friends" signal. Public games are discoverable in the lobby instead
  -- (pushing every casual public game to all friends is notification spam),
  -- and private games require a direct code share.
  IF NEW.access != 'friends' THEN
    RETURN NEW;
  END IF;

  SELECT display_name INTO v_display_name
  FROM public.user_profiles WHERE id = NEW.created_by;

  FOR r IN
    SELECT
      CASE WHEN user_id_1 = NEW.created_by THEN user_id_2
           ELSE user_id_1
      END AS friend_id
    FROM public.relationships
    WHERE status = 'accepted'
      AND (user_id_1 = NEW.created_by OR user_id_2 = NEW.created_by)
  LOOP
    PERFORM private.send_push_notification(
      p_user_id => r.friend_id,
      p_title   => COALESCE(v_display_name, 'A friend') || ' started a game',
      p_body    => 'Join now to play.',
      p_data    => jsonb_build_object(
        'category',  'game_invite',
        'deep_link', '/join/' || NEW.short_code
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_game_inserted_notify_invite
  AFTER INSERT ON public.games
  FOR EACH ROW EXECUTE FUNCTION private.notify_game_invite();

-- ── notify_friend_request ─────────────────────────────────────────────────────
-- Fires after a pending relationship is inserted and notifies the addressee
-- (the user who did NOT send the request).

CREATE OR REPLACE FUNCTION private.notify_friend_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_addressee_id uuid;
  v_display_name text;
BEGIN
  IF NEW.status != 'pending' THEN
    RETURN NEW;
  END IF;

  v_addressee_id := CASE
    WHEN NEW.initiated_by = NEW.user_id_1 THEN NEW.user_id_2
    ELSE NEW.user_id_1
  END;

  SELECT display_name INTO v_display_name
  FROM public.user_profiles WHERE id = NEW.initiated_by;

  PERFORM private.send_push_notification(
    p_user_id => v_addressee_id,
    p_title   => COALESCE(v_display_name, 'Someone') || ' wants to be friends',
    p_body    => 'Tap to respond.',
    p_data    => jsonb_build_object(
      'category',  'friend_request',
      'deep_link', '/social'
    )
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_relationship_inserted_notify_friend_request
  AFTER INSERT ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION private.notify_friend_request();

-- ── Periodic FCM token refresh ────────────────────────────────────────────────
-- Calls the refresh-fcm-token edge function every 50 minutes so the cached
-- OAuth token never expires (tokens last 60 minutes).
-- Follows the same pattern as notify_rating_update: URL from app_config,
-- secret from Vault. No-op with WARNING if either is not configured.

CREATE OR REPLACE FUNCTION private.call_refresh_fcm_token()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_url    text;
  v_secret text;
BEGIN
  SELECT value INTO v_url
  FROM private.app_config WHERE key = 'serverless_base_url';

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'serverless_secret';

  IF v_url IS NULL OR v_url = '' THEN
    RAISE WARNING 'refresh-fcm-token skipped: serverless_base_url not configured';
    RETURN;
  END IF;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'refresh-fcm-token skipped: serverless_secret not in Vault';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/refresh-fcm-token',
    headers := jsonb_build_object(
      'Content-Type',     'application/json',
      'x-webhook-secret', v_secret
    ),
    body    := '{}'::jsonb
  );
END;
$$;

SELECT cron.unschedule('refresh-fcm-token')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'refresh-fcm-token');

SELECT cron.schedule(
  'refresh-fcm-token',
  '*/50 * * * *',
  $cron$ SELECT private.call_refresh_fcm_token(); $cron$
);
