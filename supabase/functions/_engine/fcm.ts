/**
 * FCM (HTTP v1) sender — mints and **caches its own OAuth access token in
 * process**, replacing the former `refresh-fcm-token` function + pg_cron +
 * `app_config` token cache. Postgres couldn't sign an RS256 JWT, so the token
 * was minted out-of-band and stashed in the DB; the edge function mints it
 * directly.
 *
 * Token minting is delegated to `google-auth-library`'s `JWT` client, which
 * signs the service-account JWT, exchanges it for a bearer, and caches +
 * auto-refreshes it — so warm instances reuse one token without hand-rolling
 * the RS256 sign + OAuth exchange.
 *
 * This module is pure FCM — no database access. The Supabase concern (FID
 * lookup + stale-device pruning) lives in {@link ../notify.ts#pushToUser}.
 *
 * If Firebase isn't configured (no `FIREBASE_*` secrets), callers should check
 * {@link getFirebaseEnv} before calling {@link sendNotifications}.
 */

import type { FirebaseEnv } from "engine/env.ts";
import { JWT } from "google-auth-library";

/** The notification payload sent to each FCM recipient. Boundary type for the
 * FCM HTTP v1 API — defined here, not in the types module, because it belongs
 * to this transport layer. */
export interface NotificationMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}

let jwtClient: JWT | null = null;

/** `error.status` values that mean the installation is permanently dead — safe
 * to prune from `device_installations`. Deliberately narrow: transient statuses
 * (5xx / `QUOTA_EXCEEDED`) are left for the next send to retry; `INVALID_ARGUMENT`
 * is excluded because it covers both a bad FID and a malformed payload. */
const PRUNABLE_STATUS = new Set(["UNREGISTERED"]);

const firebaseAccessToken = async (
  firebaseEnv: FirebaseEnv,
): Promise<string> => {
  jwtClient ??= new JWT({
    email: firebaseEnv.clientEmail,
    key: firebaseEnv.key,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const { token } = await jwtClient.getAccessToken();
  if (!token) throw new Error("FCM access token unavailable");
  return token;
};

/** Send `message` to each FID and return settled results. Each result carries
 * a `prunable` flag that the caller uses to remove permanently dead devices.
 * Errors (network failures, token issues) reject the individual settled result;
 * the caller's `Promise.allSettled` wrapper absorbs them without interrupting
 * the batch. */
export const sendNotifications = async (
  firebaseEnv: FirebaseEnv,
  message: NotificationMessage,
  fids: string[],
) => {
  const bearer = await firebaseAccessToken(firebaseEnv);
  const url =
    `https://fcm.googleapis.com/v1/projects/${firebaseEnv.projectId}/messages:send`;

  return Promise.allSettled(
    fids.map(async (fid) => {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${bearer}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            fid,
            notification: { title: message.title, body: message.body },
            data: message.data ?? {},
          },
        }),
      });
      if (!res.ok) {
        // Cast: FCM error envelope shape — a known boundary type from the API.
        const body = (await res.json()) as { error?: { status?: string } };
        const status = body?.error?.status ?? "";
        console.error(`FCM send failed for ${fid}: ${res.status} ${status}`);
        return { fid, prunable: PRUNABLE_STATUS.has(status) };
      }
      return { fid, prunable: false };
    }),
  );
};
