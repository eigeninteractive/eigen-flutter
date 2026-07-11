/**
 * Tests of the twin-fixture runner itself (driven by an inline tic-tac-toe
 * unit so every failure path is exercised), plus the engine's dogfood run:
 * the shared fixtures under `_lib/game/fixtures/` executed against the TS
 * example rules — the same files the Dart side runs in
 * `test/engine/example_twin_fixtures_test.dart`.
 */

import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { z } from "zod";
import {
  IllegalMoveError,
  passthroughObservation,
} from "engine/game-engine.ts";
import {
  type ActionCase,
  deepEquals,
  evaluateTwinCase,
  twinFixtureTests,
} from "engine/twin-fixtures.ts";
import { gameModule } from "lib/game.ts";
import type { GameRules } from "types/engine.types.ts";

// ── Inline sample unit (tic-tac-toe-like, with an illegal-move path) ──────────

const stateSchema = z.object({
  board: z.array(z.number().nullable()).length(9),
});
const actionSchema = z.object({ cell: z.number().int() });
const configSchema = z.object({});

const sampleRules: GameRules = {
  schemas: { state: stateSchema, action: actionSchema, config: configSchema },
  initialState: () => ({
    state: { board: Array(9).fill(null) },
    pending_players: [0],
  }),
  applyAction({ state, pending, data, playerIndex }) {
    const board = [...(state.board as (number | null)[])];
    const cell = data.cell as number;
    if (!pending.includes(playerIndex) || board[cell] !== null) {
      throw new IllegalMoveError("cell is taken or it is not your turn");
    }
    board[cell] = playerIndex;
    return { state: { board }, pending_players: [1 - playerIndex] };
  },
  applyLifecycle: ({ state }) => ({ state, pending_players: [] }),
  computeObservation: passthroughObservation,
  ratingPool: ({ access }) => (access === "public" ? "casual" : null),
  botSeatable: () => true,
};

const emptyBoard = Array(9).fill(null);
const boardAfter = [...emptyBoard.slice(0, 4), 0, ...emptyBoard.slice(5)];

function actionCase(overrides: Partial<ActionCase> = {}): ActionCase {
  return {
    kind: "action",
    name: "case",
    config: {},
    state: { board: emptyBoard },
    pending: [0],
    playerIndex: 0,
    action: { cell: 4 },
    expected: {
      valid: true,
      state: { board: boardAfter },
      pending: [1],
      observation: { board: boardAfter },
    },
    ...overrides,
  };
}

function singleFailure(failures: string[], fragment: string) {
  assertEquals(failures.length, 1, failures.join("\n"));
  assertStringIncludes(failures[0], fragment);
}

// ── Runner behavior ───────────────────────────────────────────────────────────

Deno.test("a fully agreeing action case passes", () => {
  assertEquals(evaluateTwinCase(sampleRules, actionCase()), []);
});

Deno.test("an expected-illegal move that is rejected passes", () => {
  const kase = actionCase({ pending: [1], expected: { valid: false } });
  assertEquals(evaluateTwinCase(sampleRules, kase), []);
});

Deno.test("rejecting a move the fixture expects to be valid fails", () => {
  const kase = actionCase({ pending: [1] });
  singleFailure(
    evaluateTwinCase(sampleRules, kase),
    "rejected a move the fixture expects to be valid",
  );
});

Deno.test("accepting a move the fixture expects to be illegal fails", () => {
  const kase = actionCase({ expected: { valid: false } });
  singleFailure(
    evaluateTwinCase(sampleRules, kase),
    "accepted a move the fixture expects to be illegal",
  );
});

Deno.test("an envelope.state mismatch fails", () => {
  const kase = actionCase({
    expected: { valid: true, state: { board: emptyBoard } },
  });
  singleFailure(
    evaluateTwinCase(sampleRules, kase),
    "envelope.state mismatch",
  );
});

Deno.test("an actor-observation mismatch fails", () => {
  const kase = actionCase({
    expected: { valid: true, observation: { board: emptyBoard } },
  });
  singleFailure(
    evaluateTwinCase(sampleRules, kase),
    "observation mismatch",
  );
});

Deno.test("an outcome expectation is checked against ongoing games", () => {
  const kase = actionCase({
    expected: {
      valid: true,
      outcome: [
        { player_index: 0, result: "win", placement: 1, team_index: 0 },
      ],
    },
  });
  singleFailure(
    evaluateTwinCase(sampleRules, kase),
    "envelope.outcome mismatch",
  );
});

Deno.test("a schema that strips fixture action fields fails", () => {
  const kase = actionCase({ action: { cell: 4, noise: 1 } });
  singleFailure(
    evaluateTwinCase(sampleRules, kase),
    "does not preserve the fixture action",
  );
});

Deno.test("fixture state that violates the state schema fails", () => {
  const kase = actionCase({ state: { wrong: 1 } });
  singleFailure(
    evaluateTwinCase(sampleRules, kase),
    "fails the TS state schema",
  );
});

Deno.test("ratingPool agreement passes and divergence fails", () => {
  const base = {
    kind: "ratingPool" as const,
    name: "case",
    minPlayers: 2,
    maxPlayers: 2,
    config: {},
  };
  assertEquals(
    evaluateTwinCase(sampleRules, {
      ...base,
      access: "public",
      expected: "casual",
    }),
    [],
  );
  assertEquals(
    evaluateTwinCase(sampleRules, {
      ...base,
      access: "private",
      expected: null,
    }),
    [],
  );
  singleFailure(
    evaluateTwinCase(sampleRules, {
      ...base,
      access: "public",
      expected: "blitz",
    }),
    'ratingPool returned "casual"',
  );
});

Deno.test("botSeatable agreement passes and divergence fails", () => {
  const base = {
    kind: "botSeatable" as const,
    name: "case",
    gameConfig: {},
    botConfig: {},
  };
  assertEquals(evaluateTwinCase(sampleRules, { ...base, expected: true }), []);
  singleFailure(
    evaluateTwinCase(sampleRules, { ...base, expected: false }),
    "botSeatable returned true",
  );
});

Deno.test("an unknown case kind is a failure", () => {
  const kase = { kind: "mystery", name: "case" } as unknown as ActionCase;
  singleFailure(evaluateTwinCase(sampleRules, kase), "unknown case kind");
});

Deno.test("deepEquals treats undefined-valued keys as absent", () => {
  assert(deepEquals({ a: 1, b: undefined }, { a: 1 }));
  assert(!deepEquals({ a: 1 }, { a: 2 }));
  assert(!deepEquals([1, 2], [2, 1]));
});

// ── Dogfood: the shared example fixtures against the TS example unit ──────────

twinFixtureTests(
  gameModule,
  new URL("../_lib/game/fixtures/", import.meta.url),
);
