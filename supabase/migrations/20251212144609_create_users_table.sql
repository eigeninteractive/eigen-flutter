-- Create private schema (not exposed via Supabase API)
CREATE SCHEMA IF NOT EXISTS private;

-- ============================================
-- Shared enum types
-- ============================================
CREATE TYPE game_status AS ENUM ('waiting', 'ready', 'active', 'finished', 'aborted');
CREATE TYPE game_access AS ENUM ('public', 'private', 'friends');
CREATE TYPE action_type AS ENUM ('user', 'bot', 'system');
CREATE TYPE game_result AS ENUM ('win', 'loss', 'draw', 'eliminated');
-- Infra-defined system event subtypes. Game implementors handle these in
-- game_handle_system_action but never add new values — only infra does.
CREATE TYPE system_action_type AS ENUM ('timeout', 'forfeit', 'auto_forfeit');
CREATE TYPE participant_type AS ENUM ('human', 'bot');

-- Users table (system/immutable)
CREATE TABLE public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE NOT NULL,
  -- Nullable: anonymous (guest) users have no email until they convert to a
  -- permanent account. UNIQUE still holds — Postgres allows multiple NULLs.
  email TEXT UNIQUE,
  payment_tier TEXT NOT NULL DEFAULT 'free',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- Bots table
-- ============================================
-- AI/bot participants. Bots receive skill ratings in player_ratings,
-- keyed by bot_id rather than user_id.
CREATE TABLE public.bots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Unique handle, e.g. 'easy_ai'. Identity lookup key, and the key the in-app
  -- driver uses to pick the matching GameModule.localBots implementation for a
  -- local bot (GameBot.username).
  username TEXT UNIQUE NOT NULL,
  -- Human-readable display name, e.g. 'Easy AI'.
  display_name TEXT NOT NULL,
  -- Optional avatar image URL.
  avatar_url TEXT,
  -- Highest game schema this bot supports (mirrors GameModule.schemaVersion).
  -- Seating refuses to place a bot into a game whose schema_version exceeds this,
  -- exactly like the human join gate. No default — the operator must state the
  -- schema the bot was written against when inserting the row.
  schema_version INT NOT NULL,
  -- Authoritative locality. true ⇒ driven by the sole human's own client (never
  -- woken, no server transport); false ⇒ a server-side bot with its own endpoint.
  -- This is the source of truth — locality is never inferred from webhook_url, so
  -- the server-bot auth scheme can evolve without changing what "local" means. The
  -- bot_transport_consistent CHECK keeps the transport column in step with it.
  is_local BOOLEAN NOT NULL,
  -- Where to wake a server-side bot when it is its turn. NULL for local bots.
  -- A server bot authenticates both its wake (incoming) and its action (outgoing)
  -- with a single per-bot HMAC secret in Vault ('bot_secret_<id>'); no key material
  -- is stored on this row.
  webhook_url TEXT,
  -- Whether this bot may participate in rated games. A non-eligible bot can never
  -- be seated into a rated game (see seat_server_bot). Defaults false so
  -- human-vs-bot games are unrated unless a bot is explicitly ranked.
  rated_eligible BOOLEAN NOT NULL DEFAULT false,
  -- Opaque per-bot parameters, chosen by the operator. Lets one implementation /
  -- deployment back many named personas (N:1) without code changes: distinct rows
  -- share code (a local GameBot class, or a server webhook_url) but differ by
  -- config. Local bot config travels to the client via get_participants (only for
  -- local bots) and is handed to GameBot.chooseAction; server bot config travels
  -- to the bot's endpoint in the wake payload. Empty by default — most bots are
  -- parameterized in code (a local GameBot's constructor) and ignore this.
  config JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- A local bot has no endpoint; a server bot has one. Keyed off the authoritative
  -- is_local flag, not the reverse.
  CONSTRAINT bot_transport_consistent CHECK (
    (is_local AND webhook_url IS NULL) OR
    (NOT is_local AND webhook_url IS NOT NULL)
  )
);

ALTER TABLE public.bots ENABLE ROW LEVEL SECURITY;

-- No direct table SELECT for clients: webhook_url is operational and need not be
-- exposed. In-game identity resolves through get_players() (SECURITY DEFINER,
-- bypasses RLS); the "Play vs AI" / "Add bot" pickers use the get_bots() RPC (safe
-- columns only).

-- Bot discovery for the "Play vs AI" / "Add bot" pickers. Returns only display-
-- safe columns (never webhook_url). This is a single-game-per-
-- deployment engine, so the whole catalog belongs to this game. is_local lets the
-- client decide whether it can drive the bot itself (local) or must rely on the
-- server wake (server); for a local bot, username keys the GameBot implementation.
CREATE OR REPLACE FUNCTION public.get_bots()
RETURNS TABLE(
  id             UUID,
  username       TEXT,
  display_name   TEXT,
  avatar_url     TEXT,
  schema_version INT,
  is_local       BOOLEAN,
  rated_eligible BOOLEAN,
  config         JSONB
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT b.id, b.username, b.display_name, b.avatar_url,
         b.schema_version,
         b.is_local,
         b.rated_eligible,
         -- Local bot config only; a server bot's config stays server-side (it
         -- travels only in the wake to the bot's own endpoint, never to clients).
         CASE WHEN b.is_local THEN b.config ELSE NULL END
  FROM public.bots b;
$$;

REVOKE EXECUTE ON FUNCTION public.get_bots() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_bots() TO authenticated;

-- Enable RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Only the owner can read their own row.
-- Cross-user reads go through get_players() (defined in the
-- user_profiles migration, which depends on this table).
CREATE POLICY "users_select_self" ON public.users
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) = id);

-- Returns true when the calling user's JWT carries the anonymous claim.
-- Anonymous (guest) users are role `authenticated` like everyone else, so this
-- claim — not the Postgres role — is the only way to scope guest capabilities.
CREATE OR REPLACE FUNCTION private.is_anonymous()
RETURNS BOOLEAN
LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT COALESCE((auth.jwt()->>'is_anonymous')::boolean, false);
$$;

-- Raises when the caller is an anonymous guest. Gate registered-only actions
-- (friends, search) on this; play actions stay open to guests.
CREATE OR REPLACE FUNCTION private.require_permanent_user()
RETURNS VOID
LANGUAGE plpgsql STABLE SET search_path = '' AS $$
BEGIN
  IF private.is_anonymous() THEN
    RAISE EXCEPTION 'This action requires a registered account';
  END IF;
END;
$$;

-- True when the given user is an anonymous guest. Used to keep guests out of
-- social features as a *target* (search results, friend requests) — the JWT
-- claim only identifies the caller, so this reads the flag from auth.users.
CREATE OR REPLACE FUNCTION private.is_anonymous_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE(
    (SELECT is_anonymous FROM auth.users WHERE id = p_user_id),
    false
  );
$$;

-- Function to handle new user signup. For a normal signup, derives the username
-- from the email prefix, sanitised to the same charset/length rules
-- update_username enforces (^[a-zA-Z0-9_.]{3,20}$). Anonymous (guest) users have
-- no email, so they get a generated `player_NNNNN` handle instead. On collision,
-- retries with a random suffix — a plain unique violation here would roll back
-- the entire signup.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  v_base     TEXT;
  v_username TEXT;
BEGIN
  IF NEW.email IS NULL THEN
    -- Guest: no email to derive from. Start with a random handle and let the
    -- retry loop resolve any collision.
    v_base     := 'player';
    v_username := 'player_' || lpad(floor(random() * 100000)::INT::TEXT, 5, '0');
  ELSE
    v_base := lower(
      regexp_replace(split_part(NEW.email, '@', 1), '[^a-zA-Z0-9_.]', '', 'g')
    );
    v_base := left(v_base, 20);
    IF v_base = '' THEN
      v_base := 'player';
    ELSIF length(v_base) < 3 THEN
      v_base := rpad(v_base, 3, '0');
    END IF;
    v_username := v_base;
  END IF;

  FOR i IN 1..10 LOOP
    BEGIN
      INSERT INTO public.users (id, username, email)
      VALUES (NEW.id, v_username, NEW.email);
      RETURN NEW;
    EXCEPTION WHEN unique_violation THEN
      -- left(…, 15) keeps base + '_' + 4 digits within the 20-char limit.
      v_username := left(v_base, 15) || '_'
        || lpad(floor(random() * 10000)::INT::TEXT, 4, '0');
    END;
  END LOOP;
  RAISE EXCEPTION 'Could not generate a unique username for %', NEW.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Trigger on auth.users insert
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger-only: never callable directly via the REST API.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- Reusable function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = '';

-- Trigger to auto-update updated_at on users table
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- RPC to update username with validation (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.update_username(new_username TEXT)
RETURNS TEXT AS $$
DECLARE
  current_user_id UUID;
BEGIN
  -- Get the current user's ID
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  
  -- Validate username format (alphanumeric, underscores, dots, 3-20 chars)
  IF new_username !~ '^[a-zA-Z0-9_.]{3,20}$' THEN
    RAISE EXCEPTION 'Username must be 3-20 characters, alphanumeric, underscores, or dots only';
  END IF;
  
  -- Check uniqueness (case-insensitive)
  IF EXISTS (
    SELECT 1 FROM public.users 
    WHERE LOWER(username) = LOWER(new_username) 
    AND id != current_user_id
  ) THEN
    RAISE EXCEPTION 'Username already taken';
  END IF;
  
  -- Update username
  UPDATE public.users 
  SET username = new_username 
  WHERE id = current_user_id;
  
  RETURN new_username;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.update_username(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.update_username(text) TO authenticated;

-- ============================================
-- Search optimizations
-- ============================================

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
CREATE INDEX IF NOT EXISTS users_username_trgm_idx ON public.users USING gist (username extensions.gist_trgm_ops);

-- ============================================
-- Account deletion
-- ============================================
-- Deletes the caller's row from auth.users. Cascade behaviour:
--
--   Via public.users (ON DELETE CASCADE from auth.users):
--     • user_profiles, relationships, player_ratings, rating_history,
--       observations — deleted automatically.
--     • participants.user_id, game_outcomes.user_id, games.created_by,
--       actions.user_id — SET NULL; game history is preserved but anonymised.
--
--   Direct from auth.users (ON DELETE CASCADE):
--     • device_tokens — deleted automatically.
--
-- Avatar file in the storage bucket is deleted client-side before this RPC
-- is called. If the client fails mid-flow the file becomes orphaned (no
-- user_profiles row will reference it, so it is invisible to other users).
--
-- The graceful teardown (cancel created lobbies, leave joined lobbies, forfeit
-- active games) then the final delete lives in private.purge_user (defined in
-- the game-infra migration), shared with cleanup_stale_anonymous_users.
CREATE OR REPLACE FUNCTION public.delete_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  PERFORM private.purge_user(v_user_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_account() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.delete_account() TO authenticated;
