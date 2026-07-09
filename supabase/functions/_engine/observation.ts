/**
 * Framework glue that drives a game's {@link GameRules} between transport and
 * persistence: eager per-seat observation fan-out, the envelope→transition
 * builder, and the deterministic per-transition RNG.
 */

import { encodeHex } from "@std/encoding/hex";
import Rand from "rand-seed";
import type {
  CommitTransitionWire,
  ComputeObservationArgs,
  Envelope,
  GameRules,
  JsonObject,
  RatingWrite,
  SeatObservationWire,
} from "types/engine.types.ts";
import { HttpError } from "./runtime.ts";

/** Project the new state into one slice per seat — the eager fan-out the commit
 * RPC then writes (Realtime can only push stored rows, so this stays eager).
 * `rules` is the game's own version unit, already resolved by the caller.
 * `args` is the hook's own contract minus the per-seat `playerIndex`, which the
 * loop supplies; the body still forwards each field explicitly so a new hook
 * arg forces a per-seat-or-shared decision here. */
export function fanOutObservations(
  rules: GameRules,
  args: Omit<ComputeObservationArgs, "playerIndex">,
): SeatObservationWire[] {
  const slices: SeatObservationWire[] = [];
  for (let seat = 0; seat < args.participantCount; seat++) {
    const slice = rules.computeObservation({
      state: args.state,
      pending: args.pending,
      playerIndex: seat,
      participantCount: args.participantCount,
      config: args.config,
      cause: args.cause,
      isReplay: args.isReplay,
    });
    // A projection may mask OTHER seats' pending status (hidden info), but it
    // must be truthful about the seat itself: the row is what gates that
    // seat's input and turn display, while the commit enforces the
    // authoritative set — a lie here soft-locks the client or produces taps
    // that always reject. Caught at the source, like assertHookState.
    if (
      slice.pending_players.includes(seat) !== args.pending.includes(seat)
    ) {
      throw new HttpError(
        500,
        `computeObservation for seat ${seat} misreports the seat's own ` +
          `pending status`,
      );
    }
    slices.push({
      player_index: seat,
      data: slice.data,
      pending_players: slice.pending_players,
    });
  }
  return slices;
}

/** Build a single commit transition from a gameModule envelope. `ratingUpdates` is
 * attached only to a finishing transition for a rated game (see `app.ts`). */
export function toTransition(
  envelope: Envelope,
  actionData: JsonObject,
  playerIndex: number | null,
  observations: SeatObservationWire[],
  ratingUpdates: RatingWrite[] | null = null,
): CommitTransitionWire {
  return {
    action_data: actionData,
    new_state: envelope.state,
    new_pending: envelope.pending_players,
    outcome: envelope.outcome ?? null,
    turn_seconds: envelope.turn_seconds ?? null,
    player_index: playerIndex,
    observations,
    rating_updates: ratingUpdates,
  };
}

/** A fresh base seed for a new game: 128 random bits, hex-encoded. Stored on
 * `game_states.rng_seed` (service-role-only — never expose it: the whole
 * randomness of the game is derivable from it). */
export function randomSeed(): string {
  return encodeHex(crypto.getRandomValues(new Uint8Array(16)));
}

/** The deterministic RNG for one transition: rand-seed's sfc32 keyed by the
 * game's base seed and the state version the envelope will commit as. The same
 * `(seed, version)` always yields the same draw sequence — a replay re-derives
 * it — and every transition gets an independent stream, so hooks draw as many
 * values as they need with no cross-invocation state. */
export function deriveRng(seed: string, version: number) {
  return new Rand(`${seed}:${version}`);
}
