/**
 * OpenSkill rating computation — pure, DB-agnostic.
 *
 * Invoked in-process by the engine on a rated game's finishing transition: the
 * EF fetches each seat's current `mu`/`sigma` from `player_ratings`
 * (`readRatingsForSeats`, defaulting a never-rated identity to openskill
 * `rating()`), zips them with the outcome it just computed into
 * {@link PlayerInput}s, and turns the posteriors into {@link RatingResult}s. The
 * EF then attaches each identity's `expected_revision` and the commit RPC writes
 * `player_ratings` + `rating_history` atomically with the game finish. This
 * module is pure: it never touches the database and is unaware of revisions or
 * the display number (the latter is derived in SQL from `(mu, sigma)`).
 */

import { rate, rating } from "openskill";
import type { PlayerInput, Rating, RatingResult } from "types/engine.types.ts";

/** Stable grouping key for the identity occupying a seat. A seat with neither
 * id (its account was purged mid-game) keys by seat, so two purged players in
 * one game are never lumped into a single identity. */
function keyOf(player: PlayerInput): string {
  if (player.user_id) return `u:${player.user_id}`;
  if (player.bot_id) return `b:${player.bot_id}`;
  return `x:${player.player_index}`;
}

/** Whether the seat still has a ratable identity — a purged seat shapes the
 * field's posteriors but gets no {@link RatingResult} of its own. */
function hasIdentity(player: PlayerInput): boolean {
  return player.user_id !== null || player.bot_id !== null;
}

/** The discriminated identity payload written to the update. Only called for
 * seats that passed {@link hasIdentity} — anything else is a bug here. */
function identityOf(player: PlayerInput): RatingResult["identity"] {
  if (player.user_id) return { user_id: player.user_id };
  if (player.bot_id) return { bot_id: player.bot_id };
  throw new Error(`Player ${player.player_index} has no identity`);
}

/** Group items into buckets sharing the same key, preserving first-seen order.
 * Every returned bucket is non-empty by construction. */
function groupBy<T>(items: T[], keyOf: (item: T) => string | number): T[][] {
  const groups = new Map<string | number, T[]>();
  for (const item of items) {
    const group = groups.get(keyOf(item));
    if (group) group.push(item);
    else groups.set(keyOf(item), [item]);
  }
  return [...groups.values()];
}

/** Rate one field of seats and return each seat's posterior by player_index.
 * Seats sharing a team_index are rated as a single team. */
function rateField(field: PlayerInput[]) {
  const teams = groupBy(field, (p) => p.team_index);
  const posteriors = rate(
    teams.map((team) => team.map((p) => rating({ mu: p.mu, sigma: p.sigma }))),
    { rank: teams.map((team) => team[0].placement) },
  );
  const bySeat = new Map<number, Rating>();
  teams.forEach((team, t) => {
    team.forEach((p, s) => {
      bySeat.set(p.player_index, posteriors[t][s]);
    });
  });
  return bySeat;
}

/** A seat's posterior, asserting rateField's invariant that it returns every
 * seat it was given. A miss means the seat was dropped — a bug, not a no-op. */
function posteriorFor(posteriors: Map<number, Rating>, index: number) {
  const posterior = posteriors.get(index);
  if (posterior === undefined) {
    throw new Error(`No posterior computed for seat ${index}`);
  }
  return posterior;
}

/** The result for an identity that holds exactly one seat (every human, every
 * single-seat bot): rated once against the true field they actually faced. */
function singleSeatUpdate(
  seat: PlayerInput,
  fieldPosteriors: Map<number, Rating>,
): RatingResult {
  const after = posteriorFor(fieldPosteriors, seat.player_index);
  return {
    identity: identityOf(seat),
    mu: after.mu,
    sigma: after.sigma,
  };
}

/** The single net update for an identity that holds several seats (a bot filling
 * multiple slots in one game).
 *
 * Each seat is an independent game result for the same identity, applied in
 * seat order to a *running* rating, and scored only against the **other**
 * identities — an entity is never rated against itself. Because the seats' moves
 * share no information, every result legitimately moves the rating.
 *
 * All seats move one underlying rating, so the identity yields exactly ONE
 * result — prior → final. That matches the schema's one row per (game, identity)
 * (`idx_rating_history_game_bot`); emitting per-seat updates would collide on
 * that unique index and roll back the whole apply. The running rating is the one
 * piece of sequential state and never escapes this function.
 */
function multiSeatUpdate(
  seats: PlayerInput[],
  field: PlayerInput[],
): RatingResult {
  const ownKey = keyOf(seats[0]);
  const opponents = field.filter((p) => keyOf(p) !== ownKey);
  const ordered = [...seats].sort((a, b) => a.player_index - b.player_index);

  const prior: Rating = { mu: ordered[0].mu, sigma: ordered[0].sigma };
  let running: Rating = prior;
  for (const seat of ordered) {
    running = posteriorFor(
      rateField([{ ...seat, ...running }, ...opponents]),
      seat.player_index,
    );
  }
  return {
    identity: identityOf(seats[0]),
    mu: running.mu,
    sigma: running.sigma,
  };
}

/** Compute every identity's new rating for one finished game.
 *
 * Exactly one result per identity — humans and bots alike — matching the one
 * rating row per (game, identity) the schema stores. The field is rated once;
 * single-seat identities read their posterior straight from that rating, while a
 * multi-seat identity is re-rated seat-by-seat into a single net result (see
 * {@link multiSeatUpdate}). The single full-field `rate()` is what every
 * single-seat player is scored against, so a human who faced a two-seat bot is
 * correctly rated against two distinct opponents.
 *
 * A seat with no identity — its account was purged mid-game — stays in the
 * field (opponents' posteriors must account for everyone they actually faced,
 * at that seat's supplied baseline) but yields no result: there is no
 * `player_ratings` row left to update, and `player_rating_xor` forbids
 * creating an identity-less one.
 */
export function computeRatings(players: PlayerInput[]): RatingResult[] {
  const fieldPosteriors = rateField(players);
  return groupBy(players, keyOf)
    .filter((seats) => hasIdentity(seats[0]))
    .map((seats) =>
      seats.length === 1
        ? singleSeatUpdate(seats[0], fieldPosteriors)
        : multiSeatUpdate(seats, players)
    );
}
