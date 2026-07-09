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

// ── Engine error codes ────────────────────────────────────────────────────────

/** The engine's stable error-code registry — one namespace across all tiers.
 *
 * SQL raises these as SQLSTATEs (`USING ERRCODE = 'EIGxx'`), so they surface
 * on `PostgrestError.code` both for the EF's gated RPCs (threaded onto
 * {@link HttpError.code}) and for the client-direct `app_*` RPCs
 * (`PostgrestException.code` in Dart). TS-raised {@link HttpError}s carry the
 * same codes, and `app.ts` returns them to clients as `{ error, code }`.
 * Everything downstream — the EF's retry classification, HTTP status mapping,
 * and the client's user-facing copy — dispatches on the code, never on the
 * message string, so copy edits cannot change behavior.
 *
 * Keep in sync with the SQL raises and the Dart `EngineErrorCodes` twin
 * (`lib/core/errors/engine_exception.dart`). */
export const EngineCode = {
  /** `player_ratings.revision` moved between the EF read and the commit — the
   * rating baseline this finish computed from is stale. Always retryable. */
  ratingConflict: "EIG01",
  /** Optimistic `game_states.version` mismatch — the board advanced. Retryable
   * for a forfeit (recompute against the new state); a user/bot move rejects it. */
  staleVersion: "EIG02",
  turnExpired: "EIG03",
  notYourTurn: "EIG04",
  gameNotActive: "EIG05",
  gameNotFound: "EIG06",
  notParticipant: "EIG07",
  gameFull: "EIG08",
  alreadyJoined: "EIG09",
  notAcceptingPlayers: "EIG10",
  friendsOnly: "EIG11",
  unsupportedSchema: "EIG12",
  usernameInvalid: "EIG13",
  usernameTaken: "EIG14",
  notAuthenticated: "EIG15",
  /** A game's `applyAction` rejected the move ({@link IllegalMoveError}). */
  illegalMove: "EIG16",
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

/** HTTP status per engine code, for RPC errors that carry one. */
const statusByCode: Readonly<Record<string, ContentfulStatusCode>> = {
  [EngineCode.ratingConflict]: 409,
  [EngineCode.staleVersion]: 409,
  [EngineCode.turnExpired]: 409,
  [EngineCode.notYourTurn]: 409,
  [EngineCode.gameNotActive]: 409,
  [EngineCode.gameNotFound]: 404,
  [EngineCode.notParticipant]: 403,
  [EngineCode.notAuthenticated]: 401,
};

/** Map an engine_* RPC error to an HTTP status. Coded errors map by `code`
 * (robust); uncoded ones (creator checks and similar EF-internal guards) fall
 * back to message matching. The client humanizes 409 as "board updated — try
 * again". */
export function rpcErrorStatus(
  message: string,
  code?: string,
): ContentfulStatusCode {
  if (code && statusByCode[code]) return statusByCode[code];
  if (message.includes("not ready")) return 409;
  if (message.includes("not found")) return 404;
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
  if (!userId) {
    throw new HttpError(401, "Unauthenticated", EngineCode.notAuthenticated);
  }
  return userId;
}
