-- Device tokens for FCM push notifications.
-- Stores one row per (user, token) pair; tokens rotate on reinstall so
-- the primary key is (user_id, token) to allow multiple tokens per user.

CREATE TABLE public.device_tokens (
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token      text        NOT NULL,
  platform   text        NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, token)
);

-- RLS is enabled with no policies: direct PostgREST access is denied for all
-- roles. All client operations go through SECURITY DEFINER RPCs (upsert_device_token,
-- delete_device_token) which bypass RLS, and notification triggers run as the
-- service role. No direct table exposure is needed or desirable.
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

-- Called by the client on sign-out to remove this install's token.
CREATE OR REPLACE FUNCTION public.delete_device_token(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  DELETE FROM public.device_tokens
  WHERE user_id = auth.uid() AND token = p_token;
END;
$$;

-- Called by the client to register or refresh a device token.
CREATE OR REPLACE FUNCTION public.upsert_device_token(
  p_token    text,
  p_platform text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.device_tokens (user_id, token, platform)
  VALUES (auth.uid(), p_token, p_platform)
  ON CONFLICT (user_id, token) DO UPDATE
    SET platform    = EXCLUDED.platform,
        updated_at  = now();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_device_token(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.delete_device_token(text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.upsert_device_token(text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.upsert_device_token(text, text) TO authenticated;

-- Monthly cleanup: remove tokens not refreshed in 90 days.
-- These are reliably stale — FCM rotates tokens periodically so an active
-- install would have re-upserted its token well within 90 days.
SELECT cron.schedule(
  'cleanup-stale-device-tokens',
  '0 3 1 * *',
  $$DELETE FROM public.device_tokens WHERE updated_at < now() - interval '90 days'$$
);
