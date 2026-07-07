/**
 * Edge function runtime infra — env access, the error type, request-body
 * validation, and the Hono app environment type.
 *
 * Supabase clients are no longer created here: `@supabase/server`'s Hono
 * middleware injects a service-role (`supabaseAdmin`) client per request, and
 * every route group's auth (user JWT / secret API key / none+HMAC) is declared
 * as a `withSupabase` mode in `app.ts`.
 */

import { HTTPException } from "@hono/hono/http-exception";
import type { ContentfulStatusCode } from "@hono/hono/utils/http-status";
import { zValidator } from "@hono/zod-validator";
import type { SupabaseContext } from "@supabase/server";
import type { Database } from "types/engine.types.ts";
import type { ZodType } from "zod";

// ── Hono app environment ───────────────────────────────────────────────────────

/** Hono env: `withSupabase<Database>` middleware stores its context here,
 * making `supabaseAdmin` a fully typed `SupabaseClient<Database>` in every
 * route handler — no downstream casts needed. */
export type AppEnv = {
  Variables: { supabaseContext: SupabaseContext<Database> };
};

// ── Env ───────────────────────────────────────────────────────────────────────

/** Read a required env var, throwing if unset. The Supabase runtime injects the
 * `SUPABASE_*` vars; set `BOT_SIGNING_SECRET` (and the `FIREBASE_*` vars) as
 * function secrets. */
export function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing env var: ${name}`);
  return value;
}

// ── Commit conflict signalling ─────────────────────────────────────────────────

/** SQLSTATEs `engine_commit_action` raises that the EF classifies for an
 * optimistic retry. Matched on `PostgrestError.code` (supabase-js surfaces a
 * raised function's SQLSTATE there) — never on the message string. Mirror of the
 * codes raised in SQL (`apply_rating_updates` and `commit_should_abstain`); keep
 * the two in sync. */
export const SqlState = {
  /** `player_ratings.revision` moved between the EF read and the commit — the
   * rating baseline this finish computed from is stale. Always retryable. */
  ratingConflict: "EIG01",
  /** Optimistic `game_states.version` mismatch — the board advanced. Retryable
   * for a forfeit (recompute against the new state); a user/bot move rejects it. */
  staleVersion: "EIG02",
} as const;

// ── Errors ────────────────────────────────────────────────────────────────────

/** The engine's throwable HTTP error — Hono's own `HTTPException`, extended
 * with the DB SQLSTATE (`code`) when the error originated from an RPC, so
 * retry logic can classify it. Because it *is* an `HTTPException`, the single
 * `onError` branch in `app.ts` renders it, `withSupabase` auth failures, and
 * zValidator failures identically. */
export class HttpError extends HTTPException {
  constructor(
    status: ContentfulStatusCode,
    message: string,
    readonly code?: string,
  ) {
    super(status, { message });
  }
}

/** Map an engine_* RPC error to an HTTP status. The two optimistic-conflict
 * SQLSTATEs map by `code` (robust); the remaining engine errors still map by
 * their message. The client humanizes 409 as "board updated — try again". */
export function rpcErrorStatus(
  message: string,
  code?: string,
): ContentfulStatusCode {
  if (code === SqlState.ratingConflict || code === SqlState.staleVersion) {
    return 409;
  }
  if (message.includes("Turn has expired")) return 409;
  if (message.includes("Not your turn")) return 409;
  if (message.includes("not active")) return 409;
  if (message.includes("not ready")) return 409;
  if (message.includes("not found")) return 404;
  if (message.includes("Not a participant")) return 403;
  if (message.includes("creator")) return 403;
  return 500;
}

/** One-line `path: message` summary of a Zod failure. Takes the structural
 * shape rather than `ZodError` so callers holding an error produced by *any*
 * zod instance (e.g. one that arrived via an app-provided schema) can use it. */
export function issueSummary(error: { issues: readonly unknown[] }): string {
  return (error.issues as { path: PropertyKey[]; message: string }[])
    .map((i) => (i.path.length ? `${i.path.join(".")}: ` : "") + i.message)
    .join("; ");
}

// ── Request validation ────────────────────────────────────────────────────────

/** zValidator over the request JSON body, failing in the engine's error shape
 * (`{ error }` via {@link HttpError} → `onError`) instead of zValidator's
 * default 400 payload. Routes read the parsed body with `c.req.valid("json")`. */
export function jsonBody<T extends ZodType>(schema: T) {
  return zValidator("json", schema, (result) => {
    if (!result.success) {
      throw new HttpError(
        400,
        `Invalid request: ${issueSummary(result.error)}`,
      );
    }
  });
}

/** Run an optimistic read→compute→commit, retrying when the attempt throws an
 * {@link HttpError} whose DB SQLSTATE (`code`) the caller deems retryable.
 *
 * The `attempt` closure MUST re-read fresh state each call: a conflicting commit
 * raises inside the RPC, which rolls the whole transaction back, so a retry sees
 * the un-mutated game state and recomputes against the fresh baseline (e.g. the
 * bumped `player_ratings.revision`). Non-retryable errors and the final attempt's
 * error propagate unchanged. */
export async function commitWithRetry<T>(
  retryable: (code: string | undefined) => boolean,
  attempt: () => Promise<T>,
  attempts = 6,
): Promise<T> {
  for (let i = 0;; i++) {
    try {
      return await attempt();
    } catch (e) {
      if (i + 1 < attempts && e instanceof HttpError && retryable(e.code)) {
        continue;
      }
      throw e;
    }
  }
}

// ── Auth ──────────────────────────────────────────────────────────────────────

/** The verified caller's user id, or 401. `userClaims` is only populated by
 * `auth: 'user'`, so this doubles as a belt-and-braces guard on user routes. */
export function requireUserId(userId: string | null | undefined): string {
  if (!userId) throw new HttpError(401, "Unauthenticated");
  return userId;
}
