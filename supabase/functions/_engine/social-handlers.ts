/**
 * Request-body schema and handlers for the engine's social group
 * (`/engine/social/*`) — game-agnostic friend writes.
 *
 * Routes are registered in `app.ts`; every one requires a verified user JWT
 * (`auth: 'user'`). Nothing here imports from `game-handlers.ts` — social
 * logic stays game-agnostic.
 *
 * Friend-event notifications are pushed directly from here (replaces the SQL
 * notify triggers). `app_search_users` stays a direct client RPC — it's a
 * latency-sensitive read that needs no server-side logic.
 */

import type { Context } from "@hono/hono";
import { z } from "zod";
import { notifyUsers } from "./notify.ts";
import {
  acceptFriendRequest,
  removeFriend,
  sendFriendRequest,
} from "./repo.ts";
import { type AppEnv, HttpError, requireUserId } from "./runtime.ts";

export const targetBody = z.object({ target_user_id: z.string() });

/** All friend writes require a registered account. The EF gates the caller here
 * (from the JWT) so the gated RPCs no longer re-check the caller via the SQL
 * `is_anonymous_user()` read. The *target*'s guest status is still checked in
 * SQL — it needs the target's `auth.users` row, which isn't in the caller JWT. */
function requireRegisteredCaller(c: Context<AppEnv>): void {
  if (c.var.supabaseContext.jwtClaims?.is_anonymous === true) {
    throw new HttpError(403, "This action requires a registered account");
  }
}

/** Send a friend request, pushing the addressee — or, if it auto-accepted a
 * reverse-pending request, pushing the original requester instead. */
export async function handleFriendRequest(c: Context<AppEnv>, target: string) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  requireRegisteredCaller(c);
  if (target === userId) {
    throw new HttpError(400, "Cannot send a friend request to yourself");
  }
  const res = await sendFriendRequest(db, userId, target);
  if (res.notify_user_id) {
    const name = res.actor_display_name ?? "Someone";
    const msg = res.auto_accepted
      ? {
        title: `${name} accepted your friend request`,
        body: "Tap to view.",
        data: { category: "friend_accepted", deep_link: "/social" },
      }
      : {
        title: `${name} wants to be friends`,
        body: "Tap to respond.",
        data: { category: "friend_request", deep_link: "/social" },
      };
    await notifyUsers(db, [res.notify_user_id], msg);
  }
  return c.json({ ok: true });
}

/** Accept a pending request, pushing the original requester. */
export async function handleFriendAccept(c: Context<AppEnv>, target: string) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  requireRegisteredCaller(c);
  const res = await acceptFriendRequest(db, userId, target);
  if (res.accepted && res.requester_id) {
    const name = res.accepter_display_name ?? "Someone";
    await notifyUsers(db, [res.requester_id], {
      title: `${name} accepted your friend request`,
      body: "Tap to view.",
      data: { category: "friend_accepted", deep_link: "/social" },
    });
  }
  return c.json({ ok: true });
}

/** Remove a friend or withdraw a pending request (no notification). */
export async function handleFriendRemove(c: Context<AppEnv>, target: string) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  requireRegisteredCaller(c);
  await removeFriend(db, userId, target);
  return c.json({ ok: true });
}
