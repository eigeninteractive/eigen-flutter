-- User profiles table (user editable)
CREATE TABLE public.user_profiles (
  id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL CHECK (char_length(trim(display_name)) >= 2 AND char_length(display_name) <= 100),
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read all profiles (needed to display opponent info)
CREATE POLICY "user_profiles_select" ON public.user_profiles
  FOR SELECT
  TO authenticated
  USING (true);

-- Users can update their own profile only
-- (INSERT not needed - profiles are auto-created by trigger)
CREATE POLICY "user_profiles_update" ON public.user_profiles
  FOR UPDATE
  TO authenticated
  USING ((SELECT auth.uid()) = id)
  WITH CHECK ((SELECT auth.uid()) = id);

-- Auto-create profile on user creation (with avatar from Google auth)
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER AS $$
DECLARE
  google_avatar TEXT;
BEGIN
  -- Get avatar URL from auth.users metadata
  SELECT raw_user_meta_data->>'avatar_url' INTO google_avatar
  FROM auth.users WHERE id = NEW.id;
  
  INSERT INTO public.user_profiles (id, display_name, avatar_url)
  VALUES (NEW.id, NEW.username, google_avatar);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE TRIGGER on_user_created
  AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

-- Trigger-only: never callable directly via the REST API.
REVOKE EXECUTE ON FUNCTION public.handle_new_user_profile() FROM PUBLIC, anon, authenticated;

-- Trigger to auto-update updated_at on user_profiles table
CREATE TRIGGER update_user_profiles_updated_at
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================
-- Public players RPC
-- ============================================
-- Unified identity lookup for both human users and bots, returning only
-- public-safe columns (no email, no payment_tier).
--
-- Bypasses the self-only RLS on users via SECURITY DEFINER so any
-- authenticated caller can look up other players' public fields.
-- display_name is non-null for both branches:
--   humans: user_profiles.display_name NOT NULL (defaulted to username on signup)
--   bots:   bots.display_name NOT NULL
CREATE OR REPLACE FUNCTION public.get_players(p_ids UUID[])
RETURNS TABLE(id UUID, username TEXT, display_name TEXT, avatar_url TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT u.id, u.username, up.display_name, up.avatar_url
  FROM public.users u
  JOIN public.user_profiles up ON up.id = u.id
  WHERE u.id = ANY(p_ids)
  UNION ALL
  SELECT b.id, b.username, b.display_name, b.avatar_url
  FROM public.bots b
  WHERE b.id = ANY(p_ids);
$$;

REVOKE EXECUTE ON FUNCTION public.get_players(UUID[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_players(UUID[]) TO authenticated;

-- ============================================
-- Relationships table (Friends)
-- ============================================
CREATE TYPE public.relationship_status AS ENUM ('pending', 'accepted', 'blocked');

CREATE TABLE public.relationships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id_1 UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user_id_2 UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  initiated_by UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status public.relationship_status NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT canonical_ordering CHECK (user_id_1 < user_id_2),
  CONSTRAINT unique_relationship UNIQUE (user_id_1, user_id_2)
);

-- Indices
CREATE INDEX idx_relationships_user_id_1 ON public.relationships(user_id_1);
CREATE INDEX idx_relationships_user_id_2 ON public.relationships(user_id_2);
CREATE INDEX idx_relationships_status ON public.relationships(status);

-- Enable RLS
ALTER TABLE public.relationships ENABLE ROW LEVEL SECURITY;

CREATE POLICY "relationships_select" ON public.relationships
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) IN (user_id_1, user_id_2));

-- Trigger to auto-update updated_at on relationships table
CREATE TRIGGER update_relationships_updated_at
  BEFORE UPDATE ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================
-- Friends view
-- ============================================
-- Symmetric view for easy querying.
CREATE OR REPLACE VIEW public.friends_view
  WITH (security_invoker = on)
AS
SELECT user_id_1 AS user_id, user_id_2 AS friend_id, status, initiated_by, created_at, updated_at
FROM public.relationships
WHERE user_id_1 = (SELECT auth.uid())
UNION ALL
SELECT user_id_2 AS user_id, user_id_1 AS friend_id, status, initiated_by, created_at, updated_at
FROM public.relationships
WHERE user_id_2 = (SELECT auth.uid());

-- ============================================
-- Search optimizations
-- ============================================

CREATE INDEX IF NOT EXISTS user_profiles_display_name_trgm_idx ON public.user_profiles USING gist (display_name extensions.gist_trgm_ops);
