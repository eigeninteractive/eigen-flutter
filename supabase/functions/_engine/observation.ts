/**
 * Framework glue that drives {@link GameEngine} between transport and persistence:
 * eager per-seat observation fan-out, the envelope→transition builder, and the
 * deterministic per-transition RNG.
 */

import { encodeHex } from "@std/encoding/hex";
import Rand from "rand-seed";
import type {
  CommitTransitionWire,
  ComputeObservationArgs,
  Envelope,
  GameEngine,
  JsonObject,
  RatingWrite,
  SeatObservationWire,
} from "types/engine.types.ts";

/** Project the new state into one slice per seat — the eager fan-out the commit
 * RPC then writes (Realtime can only push stored rows, so this stays eager).
 * `args` is the hook's own contract minus the per-seat `playerIndex`, which the
 * loop supplies; the body still forwards each field explicitly so a new hook
 * arg forces a per-seat-or-shared decision here. */
export function fanOutObservations(
  gameEngine: GameEngine,
  args: Omit<ComputeObservationArgs, "playerIndex">,
): SeatObservationWire[] {
  const slices: SeatObservationWire[] = [];
  for (let seat = 0; seat < args.participantCount; seat++) {
    const slice = gameEngine.computeObservation({
      state: args.state,
      pending: args.pending,
      playerIndex: seat,
      participantCount: args.participantCount,
      config: args.config,
      schemaVersion: args.schemaVersion,
      isReplay: args.isReplay,
    });
    slices.push({
      player_index: seat,
      data: slice.data,
      pending_players: slice.pending_players,
    });
  }
  return slices;
}

/** Build a single commit transition from a gameEngine envelope. `ratingUpdates` is
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
