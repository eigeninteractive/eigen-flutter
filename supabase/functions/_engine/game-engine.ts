/**
 * GameEngine authoring helpers — the small runtime companions to the
 * {@link GameEngine} contract.
 *
 * The contract and all of its types live in {@link ../_types/engine.types.ts};
 * this module adds the pure helpers an app's `_lib/game.ts` reaches for
 * ({@link IllegalMoveError}, the perfect-information
 * {@link passthroughObservation}) plus the schema boundary the harness applies
 * around every hook call: {@link schemasFor} picks the game's `schema_version`
 * entry from {@link GameEngine.schemas}, {@link parseClientPayload} /
 * {@link parseStoredPayload} parse a payload through it, and
 * {@link assertHookState} validates the state a hook returned before it is
 * committed. It has no Supabase/Deno runtime dependency (Zod is reached only
 * through the schema objects the app provides; Hono, reached via
 * {@link HttpError}, is runtime-agnostic), so a gameEngine built on it stays
 * unit-testable in isolation and runs unchanged under any runtime.
 */

import type { ContentfulStatusCode } from "@hono/hono/utils/http-status";
import type {
  ComputeObservationArgs,
  Envelope,
  GameEngine,
  GameSchemas,
  JsonObject,
  ObservationSlice,
} from "types/engine.types.ts";
import type { ZodType } from "zod";
import { HttpError, issueSummary } from "./runtime.ts";

/** Thrown by a game's `applyAction` to reject a move that breaks the rules —
 * the *expected* failure of the hook (a mis-tap, a client bug), rendered as a
 * 400 with this message. Anything else a hook throws is treated as a game bug
 * and surfaces as a 500. Domain-level on purpose: the game states "this move
 * is illegal", the harness owns the HTTP mapping. */
export class IllegalMoveError extends Error {}

/**
 * Default `computeObservation` for perfect-information games: every seat sees
 * the full state and the true pending set. Mirrors the SQL default passthrough.
 */
export const passthroughObservation = <
  TState extends JsonObject,
  TConfig extends JsonObject,
>(
  args: ComputeObservationArgs<TState, TConfig>,
): ObservationSlice => ({
  data: args.state,
  pending_players: args.pending,
});

// ── Schema boundary ───────────────────────────────────────────────────────────

/** The gameEngine's payload schemas for `schemaVersion`, or an {@link HttpError}
 * when the version is not declared in {@link GameEngine.schemas}. Create routes
 * pass `missingStatus: 400` (the client asked for a version this deployment
 * doesn't ship); loaded-game paths keep the 500 default (a stored game newer
 * than the deployed EF is an ops error, not a caller error). */
export function schemasFor(
  gameEngine: GameEngine,
  schemaVersion: number,
  missingStatus: ContentfulStatusCode = 500,
): GameSchemas {
  const schemas = gameEngine.schemas[schemaVersion];
  if (!schemas) {
    throw new HttpError(
      missingStatus,
      `Unsupported schema_version ${schemaVersion}`,
    );
  }
  return schemas;
}

/** Parse a client-submitted payload (an action's `data`, a create request's
 * `config`) through its schema. Failure is the caller's fault → 400. Returns
 * the parsed value, so what flows onward — into hooks, the `actions` log, and
 * `games.config` — is the sanitized shape (unknown keys stripped, defaults
 * applied), never the raw request body. */
export function parseClientPayload<T>(
  schema: ZodType<T>,
  value: unknown,
  what: string,
): T {
  const result = schema.safeParse(value);
  if (!result.success) {
    throw new HttpError(400, `Invalid ${what}: ${issueSummary(result.error)}`);
  }
  return result.data;
}

/** Parse a stored payload (`game_states.state`, `games.config`) through its
 * schema. Failure means corrupted data or a schema that no longer matches what
 * this version historically wrote — an engine-side error → 500. */
export function parseStoredPayload<T>(
  schema: ZodType<T>,
  value: unknown,
  what: string,
  schemaVersion: number,
): T {
  const result = schema.safeParse(value);
  if (!result.success) {
    throw new HttpError(
      500,
      `Stored ${what} failed validation for schema_version ` +
        `${schemaVersion}: ${issueSummary(result.error)}`,
    );
  }
  return result.data;
}

/** Validate the state a hook returned against the game's version schema before
 * it is committed — catching a hook that wrote a malformed or wrong-version
 * shape at the source instead of on the next read. Validate-only: the original
 * envelope object is what gets persisted. */
export function assertHookState(
  schemas: GameSchemas,
  envelope: Envelope,
  schemaVersion: number,
): void {
  const result = schemas.state.safeParse(envelope.state);
  if (!result.success) {
    throw new HttpError(
      500,
      `Hook returned state that violates schema_version ` +
        `${schemaVersion}: ${issueSummary(result.error)}`,
    );
  }
}
