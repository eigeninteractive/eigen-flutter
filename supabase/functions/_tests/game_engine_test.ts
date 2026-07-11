/** Tests of the version boundary and the pre-commit hook guards in
 * `_engine/game-engine.ts` — all pure, no runtime dependency. */

import { assertEquals, assertThrows } from "@std/assert";
import { z } from "zod";
import {
  assertBudgetPending,
  assertForfeitPending,
  assertHookState,
  assertPendingIdentified,
  parseClientPayload,
  parseStoredPayload,
  passthroughObservation,
  rulesFor,
} from "engine/game-engine.ts";
import { EngineCode, HttpError } from "engine/runtime.ts";
import type { Envelope, GameModule, GameRules } from "types/engine.types.ts";

const schema = z.object({ moves: z.number().int() });
const schemas = { state: schema, action: schema, config: schema };

const unit = { schemas } as unknown as GameRules;
const gameModule: GameModule = { versions: { 1: unit } };

function statusOf(fn: () => unknown): number {
  const error = assertThrows(fn, HttpError);
  return (error as HttpError).status;
}

Deno.test("rulesFor resolves a shipped version's unit", () => {
  assertEquals(rulesFor(gameModule, 1), unit);
});

Deno.test("rulesFor: a missing version is a 500 with the stable code", () => {
  const error = assertThrows(
    () => rulesFor(gameModule, 2),
    HttpError,
    "schema_version 2",
  ) as HttpError;
  assertEquals(error.status, 500);
  assertEquals(error.code, EngineCode.unsupportedSchema);
});

Deno.test("rulesFor: create routes downgrade the miss to a 400", () => {
  assertEquals(statusOf(() => rulesFor(gameModule, 2, 400)), 400);
});

Deno.test("parseClientPayload returns the sanitized parse", () => {
  const loose = z.object({ a: z.number() });
  assertEquals(parseClientPayload(loose, { a: 1, b: 2 }, "action"), { a: 1 });
});

Deno.test("parseClientPayload: an invalid payload is the caller's 400", () => {
  const error = assertThrows(
    () => parseClientPayload(schema, { moves: "x" }, "action"),
    HttpError,
    "Invalid action",
  ) as HttpError;
  assertEquals(error.status, 400);
});

Deno.test("parseStoredPayload: corrupt stored data is an engine 500", () => {
  const error = assertThrows(
    () => parseStoredPayload(schema, { moves: "x" }, "state", 1),
    HttpError,
    "schema_version 1",
  ) as HttpError;
  assertEquals(error.status, 500);
});

Deno.test("assertHookState accepts schema-conforming state", () => {
  assertHookState(schemas, { state: { moves: 1 }, pending_players: [] }, 1);
});

Deno.test("assertHookState: violating state is a 500", () => {
  const envelope: Envelope = {
    state: { moves: -0.5 },
    pending_players: [],
  };
  assertEquals(statusOf(() => assertHookState(schemas, envelope, 1)), 500);
});

Deno.test("assertBudgetPending allows unbudgeted multi-pending", () => {
  assertBudgetPending(null, { state: {}, pending_players: [0, 1] }, 1);
});

Deno.test("assertBudgetPending allows a single budget-timed seat", () => {
  assertBudgetPending(30, { state: {}, pending_players: [0] }, 1);
  assertBudgetPending(30, { state: {}, pending_players: [] }, 1);
});

Deno.test("assertBudgetPending: multi-pending under a budget is a 500", () => {
  assertEquals(
    statusOf(() =>
      assertBudgetPending(30, { state: {}, pending_players: [0, 1] }, 1)
    ),
    500,
  );
});

Deno.test("assertForfeitPending accepts a removed seat", () => {
  assertForfeitPending(0, { state: {}, pending_players: [1] }, 1);
});

Deno.test("assertForfeitPending: a lingering forfeited seat is a 500", () => {
  assertEquals(
    statusOf(() =>
      assertForfeitPending(0, { state: {}, pending_players: [0, 1] }, 1)
    ),
    500,
  );
});

const roster = [
  { player_index: 0, user_id: "u1", bot_id: null },
  { player_index: 1, user_id: null, bot_id: "b1" },
  { player_index: 2, user_id: null, bot_id: null },
];

Deno.test("assertPendingIdentified accepts identified pending seats", () => {
  assertPendingIdentified(roster, { state: {}, pending_players: [0, 1] }, 1);
});

Deno.test("assertPendingIdentified: a purged pending seat is a 500", () => {
  const error = assertThrows(
    () =>
      assertPendingIdentified(roster, { state: {}, pending_players: [2] }, 1),
    HttpError,
    "seat 2",
  ) as HttpError;
  assertEquals(error.status, 500);
});

Deno.test("passthroughObservation exposes state and pending unchanged", () => {
  const slice = passthroughObservation({
    state: { moves: 3 },
    pending: [1],
    playerIndex: 0,
    participantCount: 2,
    config: {},
    cause: null,
    isReplay: false,
  });
  assertEquals(slice, { data: { moves: 3 }, pending_players: [1] });
});
