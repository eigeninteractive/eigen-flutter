-- ============================================
-- Social RPCs — friends (EF-gated) + user search (client-direct)
-- ============================================
-- engine_* friend writes driven by the social edge function (so it can emit the
-- FCM pushes), plus the client-direct app_search_users read.
--
-- Naming: engine_* = service-role, EF-only gated RPCs (REVOKEd from
-- authenticated). cron_* = pg_cron-scheduled private jobs. app_* =
-- client-direct RPCs (PostgREST, under RLS/auth). do_*/other private.* =
-- internal helpers. See docs/engine_architecture.md.
-- ============================================

-- ============================================
-- Friends RPCs (gated engine_* — driven by the social edge function)
-- ============================================
-- These three writes moved behind the `social` edge function so it can emit the
-- friend-request / accepted FCM pushes directly (the former notify_friend_request
-- trigger + /internal/notify hop are gone). Each takes the EF-verified caller id
-- (p_caller_id) and RETURNS the bits the EF needs to address a push: who to notify
-- and the actor's display name. Gated to the service role. app_search_users stays a
-- direct, client-callable RPC (a latency-sensitive read, no notification).

-- Returns: created_pending — a fresh pending request was inserted (notify the
-- addressee "<actor> wants to be friends"); auto_accepted — a reverse pending
-- request existed and was accepted instead (notify "<actor> accepted your
-- request"); notify_user_id — the user to push (the target in both cases, else
-- NULL); actor_display_name — the caller's display name.
CREATE OR REPLACE FUNCTION public.engine_send_friend_request(
  p_caller_id      UUID,
  p_target_user_id UUID
)
RETURNS TABLE(
  created_pending    BOOLEAN,
  auto_accepted      BOOLEAN,
  notify_user_id     UUID,
  actor_display_name TEXT
) AS $$
DECLARE
  v_u1       UUID;
  v_u2       UUID;
  v_inserted INT;
  v_accepted BOOLEAN;
BEGIN
  -- Caller-guest and self-target are gated by the social EF (from the JWT). The
  -- target's guest status is checked here — it needs the target's auth.users row,
  -- which the caller's JWT cannot supply.
  IF private.is_anonymous_user(p_target_user_id) THEN
    RAISE EXCEPTION 'Cannot send a friend request to a guest';
  END IF;

  SELECT display_name INTO actor_display_name
  FROM public.user_profiles WHERE id = p_caller_id;

  v_u1 := LEAST(p_caller_id, p_target_user_id);
  v_u2 := GREATEST(p_caller_id, p_target_user_id);

  -- A pending request from the target means sending one back accepts it.
  IF EXISTS (
    SELECT 1 FROM public.relationships
    WHERE user_id_1 = v_u1 AND user_id_2 = v_u2
      AND status = 'pending' AND initiated_by = p_target_user_id
  ) THEN
    SELECT a.accepted INTO v_accepted
    FROM public.engine_accept_friend_request(p_caller_id, p_target_user_id) a;
    created_pending := false;
    auto_accepted   := COALESCE(v_accepted, false);
    notify_user_id  := CASE WHEN auto_accepted THEN p_target_user_id END;
    RETURN NEXT;
    RETURN;
  END IF;

  INSERT INTO public.relationships (user_id_1, user_id_2, initiated_by, status)
  VALUES (v_u1, v_u2, p_caller_id, 'pending')
  ON CONFLICT (user_id_1, user_id_2) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  created_pending := v_inserted > 0;
  auto_accepted   := false;
  notify_user_id  := CASE WHEN created_pending THEN p_target_user_id END;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.engine_send_friend_request(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Returns: accepted — a pending request was transitioned to accepted (notify the
-- original requester "<accepter> accepted your friend request"); requester_id —
-- the user to push (the original initiator); accepter_display_name — the caller's
-- display name.
CREATE OR REPLACE FUNCTION public.engine_accept_friend_request(
  p_caller_id      UUID,
  p_target_user_id UUID
)
RETURNS TABLE(
  accepted               BOOLEAN,
  requester_id           UUID,
  accepter_display_name  TEXT
) AS $$
DECLARE
  v_u1      UUID;
  v_u2      UUID;
  v_updated INT;
BEGIN
  -- Caller-guest is gated by the social EF (from the JWT).
  v_u1 := LEAST(p_caller_id, p_target_user_id);
  v_u2 := GREATEST(p_caller_id, p_target_user_id);

  UPDATE public.relationships
  SET status = 'accepted', updated_at = NOW()
  WHERE user_id_1 = v_u1 AND user_id_2 = v_u2
    AND status = 'pending' AND initiated_by = p_target_user_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  accepted     := v_updated > 0;
  requester_id := CASE WHEN accepted THEN p_target_user_id END;
  SELECT display_name INTO accepter_display_name
  FROM public.user_profiles WHERE id = p_caller_id;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.engine_accept_friend_request(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.engine_remove_friend(
  p_caller_id      UUID,
  p_target_user_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_u1 UUID;
  v_u2 UUID;
BEGIN
  -- Caller-guest is gated by the social EF (from the JWT).
  v_u1 := LEAST(p_caller_id, p_target_user_id);
  v_u2 := GREATEST(p_caller_id, p_target_user_id);

  DELETE FROM public.relationships
  WHERE user_id_1 = v_u1 AND user_id_2 = v_u2;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.engine_remove_friend(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.app_search_users(p_query TEXT)
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
  -- Exclude anonymous guests: they are throwaway accounts and cannot be friended.
  JOIN auth.users au ON au.id = u.id AND NOT au.is_anonymous
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

REVOKE EXECUTE ON FUNCTION public.app_search_users(text) FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION public.app_search_users(text) TO authenticated;
