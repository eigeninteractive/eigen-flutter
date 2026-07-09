-- The private schema, extensions, and shared enum types are created in the
-- foundation migration (20251212144600_foundation.sql), which runs first.

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
  -- with a per-bot HMAC key the edge function derives on demand as
  -- HMAC(BOT_SIGNING_SECRET, bot_id) (see _engine/bot_auth.ts); no key material is
  -- stored on this row or in Vault.
  webhook_url TEXT,
  -- Whether this bot may participate in rated games. A non-eligible bot can never
  -- be seated into a rated game (see seat_server_bot). Defaults false so
  -- human-vs-bot games are unrated unless a bot is explicitly ranked.
  rated_eligible BOOLEAN NOT NULL DEFAULT false,
  -- Per-bot parameters, chosen by the operator. Two uses, no schema imposed by
  -- infra: (1) persona tuning — one implementation backs many named personas (N:1)
  -- without code changes (distinct rows share a local class or server webhook_url
  -- but differ by config); (2) capability declaration — what game configs the bot
  -- supports (e.g. {"variants":["standard"]}), interpreted by the game's
  -- botSeatable hook — in TypeScript on the server (GameRules.botSeatable, the
  -- seating authority) and its Dart twin (GameModule.botSeatable) for local picker
  -- filtering. Public read-only
  -- reference data: app_bots exposes it for BOTH local and server bots, so never
  -- put secrets here (a server bot's wake/action key is derived from
  -- BOT_SIGNING_SECRET, never stored). A local
  -- bot's config is handed to GameBot.chooseAction; a server bot's also travels in
  -- the wake payload. Empty by default.
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
-- exposed. In-game identity resolves through app_players() (SECURITY DEFINER,
-- bypasses RLS); the "Play vs AI" / "Add bot" pickers use the app_bots() RPC (safe
-- columns only).

-- Bot discovery for the "Play vs AI" / "Add bot" pickers. Returns only display-
-- safe columns (never webhook_url). This is a single-game-per-
-- deployment engine, so the whole catalog belongs to this game. is_local lets the
-- client decide whether it can drive the bot itself (local) or must rely on the
-- server wake (server); for a local bot, username keys the GameBot implementation.
CREATE OR REPLACE FUNCTION public.app_bots()
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
         -- Exposed for both local and server bots: persona tuning + capability
         -- declaration (read by the TS/Dart GameRules.botSeatable twins). Never secret.
         b.config
  FROM public.bots b
  -- Deterministic order so the pickers' "first available" default is stable.
  ORDER BY b.display_name;
$$;

REVOKE EXECUTE ON FUNCTION public.app_bots() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.app_bots() TO authenticated;

-- Enable RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Only the owner can read their own row.
-- Cross-user reads go through app_players() (defined in the
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
-- app_update_username enforces (^[a-zA-Z0-9_.]{3,20}$). Anonymous (guest) users have
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
CREATE OR REPLACE FUNCTION public.app_update_username(new_username TEXT)
RETURNS TEXT AS $$
DECLARE
  current_user_id UUID;
BEGIN
  -- Get the current user's ID
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'EIG15';
  END IF;
  
  -- Validate username format (alphanumeric, underscores, dots, 3-20 chars)
  IF new_username !~ '^[a-zA-Z0-9_.]{3,20}$' THEN
    RAISE EXCEPTION 'Username must be 3-20 characters, alphanumeric, underscores, or dots only'
      USING ERRCODE = 'EIG13';
  END IF;
  
  -- Check uniqueness (case-insensitive)
  IF EXISTS (
    SELECT 1 FROM public.users 
    WHERE LOWER(username) = LOWER(new_username) 
    AND id != current_user_id
  ) THEN
    RAISE EXCEPTION 'Username already taken' USING ERRCODE = 'EIG14';
  END IF;
  
  -- Update username
  UPDATE public.users 
  SET username = new_username 
  WHERE id = current_user_id;
  
  RETURN new_username;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.app_update_username(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.app_update_username(text) TO authenticated;

-- ============================================
-- Search optimizations
-- ============================================
-- pg_trgm is created in the foundation migration.
CREATE INDEX IF NOT EXISTS users_username_trgm_idx ON public.users USING gist (username extensions.gist_trgm_ops);

