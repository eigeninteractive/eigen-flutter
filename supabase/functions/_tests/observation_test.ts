/** Tests of the observation fan-out, the transition builder, and the
 * deterministic per-transition RNG in `_engine/observation.ts`. */

import {
  assert,
  assertEquals,
  assertMatch,
  assertNotEquals,
  assertThrows,
} from "@std/assert";
import {
  deriveRng,
  fanOutObservations,
  randomSeed,
  toTransition,
} from "engine/observation.ts";
import { passthroughObservation } from "engine/game-engine.ts";
import { HttpError } from "engine/runtime.ts";
import type { GameRules } from "types/engine.types.ts";

const fanArgs = {
  state: { moves: 2 },
  pending: [1],
  participantCount: 3,
  config: {},
  cause: null,
  isReplay: false,
};

/** A rules unit that only projects observations — all the fan-out reads. */
function rulesWith(
  computeObservation: GameRules["computeObservation"],
): GameRules {
  return { computeObservation } as GameRules;
}

Deno.test("fanOutObservations projects one slice per seat", () => {
  const slices = fanOutObservations(rulesWith(passthroughObservation), fanArgs);
  assertEquals(slices.length, 3);
  assertEquals(slices.map((s) => s.player_index), [0, 1, 2]);
  for (const slice of slices) {
    assertEquals(slice.data, { moves: 2 });
    assertEquals(slice.pending_players, [1]);
  }
});

Deno.test("a slice misreporting the seat's own pending status is a 500", () => {
  // Claims *every* seat is pending — a lie for seats 0 and 2.
  const lying = rulesWith(({ state, playerIndex }) => ({
    data: state,
    pending_players: [playerIndex],
  }));
  const error = assertThrows(
    () => fanOutObservations(lying, fanArgs),
    HttpError,
    "misreports the seat's own pending status",
  );
  assertEquals(error.status, 500);
});

Deno.test("hiding OTHER seats' pending status is allowed", () => {
  // Truthful about self, silent about others: seat 1 sees itself pending,
  // other seats see nobody.
  const masking = rulesWith(({ state, pending, playerIndex }) => ({
    data: state,
    pending_players: pending.includes(playerIndex) ? [playerIndex] : [],
  }));
  const slices = fanOutObservations(masking, fanArgs);
  assertEquals(slices.map((s) => s.pending_players), [[], [1], []]);
});

Deno.test("toTransition defaults absent envelope fields to null", () => {
  const transition = toTransition(
    { state: { moves: 1 }, pending_players: [0] },
    { cell: 4 },
    0,
    [],
  );
  assertEquals(transition, {
    action_data: { cell: 4 },
    new_state: { moves: 1 },
    new_pending: [0],
    outcome: null,
    turn_seconds: null,
    player_index: 0,
    observations: [],
    rating_updates: null,
  });
});

Deno.test("toTransition carries outcome, override, and ratings", () => {
  const outcome = [
    { player_index: 0, result: "win" as const, placement: 1, team_index: 0 },
  ];
  const transition = toTransition(
    { state: {}, pending_players: [], outcome, turn_seconds: 15 },
    {},
    null,
    [],
    [],
  );
  assertEquals(transition.outcome, outcome);
  assertEquals(transition.turn_seconds, 15);
  assertEquals(transition.player_index, null);
  assertEquals(transition.rating_updates, []);
});

Deno.test("randomSeed is 128 random bits, hex-encoded", () => {
  const seed = randomSeed();
  assertMatch(seed, /^[0-9a-f]{32}$/);
  assertNotEquals(seed, randomSeed());
});

Deno.test("deriveRng: the same (seed, version) replays the same draws", () => {
  const draws = () => {
    const rng = deriveRng("base-seed", 7);
    return [rng.next(), rng.next(), rng.next()];
  };
  assertEquals(draws(), draws());
});

Deno.test("deriveRng: each version gets an independent stream", () => {
  assertNotEquals(
    deriveRng("base-seed", 1).next(),
    deriveRng("base-seed", 2).next(),
  );
});

Deno.test("deriveRng draws floats in [0, 1)", () => {
  const rng = deriveRng("base-seed", 1);
  for (let i = 0; i < 100; i++) {
    const draw = rng.next();
    assert(draw >= 0 && draw < 1, `draw ${draw} out of range`);
  }
});
