-- Public bucket: avatar files are accessible via their public URL without auth.
-- Paths are UUIDs, making enumeration infeasible. Profile photos are semi-public
-- by nature (shown to other players), so a public bucket is the right trade-off.
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- Authenticated users may upload only to their own path.
CREATE POLICY "Users can upload own avatar" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND name = (SELECT auth.uid())::text
  );

-- Authenticated users may overwrite their own avatar.
CREATE POLICY "Users can update own avatar" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND name = (SELECT auth.uid())::text)
  WITH CHECK (bucket_id = 'avatars' AND name = (SELECT auth.uid())::text);

-- No broad SELECT policy is needed: the public bucket serves object URLs directly
-- via Supabase's HTTP layer without any RLS check. cached_network_image fetches
-- avatars by URL and never queries storage.objects. Removing the broad policy
-- prevents clients from enumerating all avatar filenames via the storage API.
--
-- Authenticated users can introspect their own object only (needed if the
-- profile editor checks whether an existing avatar is present before uploading).
CREATE POLICY "Users can read own avatar object" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'avatars' AND name = (SELECT auth.uid())::text);

-- Authenticated users may delete their own avatar (called client-side before delete_account).
CREATE POLICY "Users can delete own avatar" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'avatars' AND name = (SELECT auth.uid())::text);
