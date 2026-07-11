/** Tests of the pure OpenSkill rating computation in `_engine/ratings.ts` —
 * relational assertions (who moves which way), not golden numbers, so an
 * openskill version bump doesn't invalidate the suite. */

import { assert, assertEquals } from "@std/assert";
import { computeRatings } from "engine/ratings.ts";
import type { PlayerInput, RatingResult } from "types/engine.types.ts";

/** OpenSkill defaults for a never-rated identity. */
const MU = 25;
const SIGMA = 25 / 3;

function seat(overrides: Partial<PlayerInput>): PlayerInput {
  return {
    player_index: 0,
    user_id: null,
    bot_id: null,
    mu: MU,
    sigma: SIGMA,
    placement: 1,
    team_index: 0,
    ...overrides,
  };
}

function resultFor(
  results: RatingResult[],
  identity: RatingResult["identity"],
): RatingResult {
  const match = results.find(
    (r) => JSON.stringify(r.identity) === JSON.stringify(identity),
  );
  assert(match, `no result for ${JSON.stringify(identity)}`);
  return match;
}

Deno.test("1v1: winner's mu rises, loser's falls, both sigmas shrink", () => {
  const results = computeRatings([
    seat({ player_index: 0, user_id: "winner", placement: 1, team_index: 0 }),
    seat({ player_index: 1, user_id: "loser", placement: 2, team_index: 1 }),
  ]);
  assertEquals(results.length, 2);
  const winner = resultFor(results, { user_id: "winner" });
  const loser = resultFor(results, { user_id: "loser" });
  assert(winner.mu > MU, `winner mu ${winner.mu} should exceed ${MU}`);
  assert(loser.mu < MU, `loser mu ${loser.mu} should drop below ${MU}`);
  assert(winner.sigma < SIGMA);
  assert(loser.sigma < SIGMA);
});

Deno.test("a draw between equal priors moves both identically", () => {
  const results = computeRatings([
    seat({ player_index: 0, user_id: "a", placement: 1, team_index: 0 }),
    seat({ player_index: 1, user_id: "b", placement: 1, team_index: 1 }),
  ]);
  const a = resultFor(results, { user_id: "a" });
  const b = resultFor(results, { user_id: "b" });
  assertEquals(a.mu, b.mu);
  assertEquals(a.sigma, b.sigma);
});

Deno.test("bots are rated like humans, keyed by bot identity", () => {
  const results = computeRatings([
    seat({ player_index: 0, user_id: "u1", placement: 2, team_index: 0 }),
    seat({ player_index: 1, bot_id: "b1", placement: 1, team_index: 1 }),
  ]);
  assertEquals(results.length, 2);
  assert(resultFor(results, { bot_id: "b1" }).mu > MU);
});

Deno.test("a purged seat shapes the field but yields no result", () => {
  const results = computeRatings([
    seat({ player_index: 0, user_id: "u1", placement: 1, team_index: 0 }),
    seat({ player_index: 1, placement: 2, team_index: 1 }),
  ]);
  assertEquals(results.length, 1);
  const survivor = resultFor(results, { user_id: "u1" });
  assert(survivor.mu > MU, "beating the purged seat still counts");
});

Deno.test("a multi-seat bot yields exactly one net result", () => {
  const results = computeRatings([
    seat({ player_index: 0, bot_id: "b1", placement: 1, team_index: 0 }),
    seat({ player_index: 1, bot_id: "b1", placement: 3, team_index: 1 }),
    seat({ player_index: 2, user_id: "u1", placement: 2, team_index: 2 }),
  ]);
  assertEquals(results.length, 2);
  const bot = resultFor(results, { bot_id: "b1" });
  assert(bot.mu !== MU, "both seats' outcomes must move the single rating");
  resultFor(results, { user_id: "u1" });
});

Deno.test("seats sharing a team_index are rated as one team", () => {
  const results = computeRatings([
    seat({ player_index: 0, user_id: "a1", placement: 1, team_index: 0 }),
    seat({ player_index: 1, user_id: "a2", placement: 1, team_index: 0 }),
    seat({ player_index: 2, user_id: "d1", placement: 2, team_index: 1 }),
    seat({ player_index: 3, user_id: "d2", placement: 2, team_index: 1 }),
  ]);
  assertEquals(results.length, 4);
  const a1 = resultFor(results, { user_id: "a1" });
  const a2 = resultFor(results, { user_id: "a2" });
  const d1 = resultFor(results, { user_id: "d1" });
  assertEquals(a1.mu, a2.mu, "equal-prior teammates move together");
  assert(a1.mu > MU);
  assert(d1.mu < MU);
});

Deno.test("the computation is deterministic", () => {
  const players = () => [
    seat({ player_index: 0, user_id: "a", placement: 1, team_index: 0 }),
    seat({ player_index: 1, user_id: "b", placement: 2, team_index: 1 }),
  ];
  assertEquals(computeRatings(players()), computeRatings(players()));
});
