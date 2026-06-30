-- Firebase Installation IDs (FIDs) for FCM push notifications.
-- One row per installation, keyed by `fid` — a FID identifies an app install and
-- is FCM's current push target (the registration token was deprecated in favour
-- of the FID). `user_id` is the currently signed-in user on that install. Because
-- `fid` is the key, signing in on a device a different account previously used
-- simply reassigns the row (the upsert's ON CONFLICT updates `user_id`), so a FID
-- maps to exactly one user — no stale association lingers. A user with several
-- devices has one row per FID.

CREATE TABLE public.device_installations (
  fid        text        PRIMARY KEY,
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  platform   text        NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- The edge function fans out by user_id (every install for the target user), so
-- index it — it is no longer the leading column of the primary key.
CREATE INDEX device_installations_user_id_idx
  ON public.device_installations (user_id);

-- RLS is enabled with no policies: direct PostgREST access is denied for all
-- roles. All client operations go through SECURITY DEFINER RPCs
-- (app_upsert_device_installation, app_delete_device_installation) which bypass RLS,
-- and the notification edge function reads the table as the service role. No
-- direct table exposure is needed or desirable.
ALTER TABLE public.device_installations ENABLE ROW LEVEL SECURITY;

-- Called by the client on sign-out to remove this install's registration. Scoped
-- to the caller so a device whose FID was already reassigned to another account
-- is left untouched.
CREATE OR REPLACE FUNCTION public.app_delete_device_installation(p_fid text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  DELETE FROM public.device_installations
  WHERE fid = p_fid AND user_id = auth.uid();
END;
$$;

-- Called by the client to register the current user on this install. Keyed on
-- `fid`, so signing in claims the device from any prior owner (ON CONFLICT
-- reassigns `user_id`) rather than stacking a second row.
CREATE OR REPLACE FUNCTION public.app_upsert_device_installation(
  p_fid      text,
  p_platform text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.device_installations (fid, user_id, platform)
  VALUES (p_fid, auth.uid(), p_platform)
  ON CONFLICT (fid) DO UPDATE
    SET user_id    = auth.uid(),
        platform   = EXCLUDED.platform,
        updated_at = now();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.app_delete_device_installation(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.app_delete_device_installation(text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.app_upsert_device_installation(text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.app_upsert_device_installation(text, text) TO authenticated;

-- No scheduled cleanup: a FID is stable per install (it does not rotate like an
-- FCM token), so there is no heartbeat to age out. Rows are removed at sign-out
-- (app_delete_device_installation), on account deletion (CASCADE from auth.users),
-- and by the edge function when FCM reports a FID permanently invalid
-- (UNREGISTERED / SENDER_ID_MISMATCH). A dead FID never targeted again simply
-- lingers, harmlessly, until the next send prunes it.
