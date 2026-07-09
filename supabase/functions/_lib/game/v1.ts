/**
 * Schema version 1 of the app's game — one self-contained {@link GameRules}
 * unit: the Zod payload contracts plus all six hooks, typed to this version's
 * shapes.
 *
 * ## Payload typing — schema-first
 *
 * Declare a Zod schema per payload (`state`, `action`, `config`) and derive
 * the types with `z.infer` — the schema is the single source of truth. The
 * engine harness parses every payload with this unit's schemas before
 * invoking its hooks, so hook bodies receive validated, typed values (never
 * raw JSON, never another version's shape), and it re-validates the state a
 * hook returns before committing it. Conventions:
 *
 * - Derive payload types as `type` aliases via `z.infer` (an `interface`
 *   fails the engine's `JsonObject` constraint).
 * - Keep schemas transform-free: what parses is what persists, and the
 *   harness validates hook output against the same `state` schema.
 *
 * When rules or shapes change incompatibly, don't edit this file's semantics —
 * copy it to `v2.ts` (importing whatever didn't change from here), make the
 * change there, and register it in `game.ts`. Games created under v1 keep
 * running against this unit until they drain.
 *
 * This shipped example is a trivial one-move game (player 0 acts once and
 * wins); replace it with your game. See docs/game_implementation_guide.md for
 * the full contract. For a hidden-info game, implement `computeObservation` to
 * reveal only each seat's slice instead of {@link passthroughObservation}.
 */

import { passthroughObservation } from "engine/game-engine.ts";
import type {
  ApplyActionArgs,
  BotSeatableArgs,
  Envelope,
  EventArgs,
  GameRules,
  InitialStateArgs,
  RatingPoolArgs,
} from "types/engine.types.ts";
import { z } from "zod";

const stateSchema = z.object({ moves: z.number().int().min(0) });
const actionSchema = z.object({});
const configSchema = z.object({});

type State = z.infer<typeof stateSchema>;
type Action = z.infer<typeof actionSchema>;
type Config = z.infer<typeof configSchema>;

class ExampleRulesV1 implements GameRules<State, Action, Config> {
  readonly schemas = {
    state: stateSchema,
    action: actionSchema,
    config: configSchema,
  };

  // Draw any setup randomness (deck shuffle, first player…) from `args.rng` —
  // a deterministic per-transition generator (`rng.next()` → float in [0, 1)).
  // This example needs none.
  initialState(_args: InitialStateArgs<Config>): Envelope<State> {
    return { state: { moves: 0 }, pending_players: [0] };
  }

  // Reject a rule-breaking move by throwing IllegalMoveError (from
  // engine/game-engine.ts) — the harness renders it as a 400. This one-move
  // example has no illegal moves.
  applyAction({
    state,
  }: ApplyActionArgs<State, Action, Config>): Envelope<State> {
    return {
      state: { moves: state.moves + 1 },
      pending_players: [],
      outcome: [
        { player_index: 0, result: "win", placement: 1, team_index: 0 },
      ],
    };
  }

  handleEvent({ state }: EventArgs<State, Config>): Envelope<State> {
    return {
      state,
      pending_players: [],
      outcome: [
        { player_index: 0, result: "win", placement: 1, team_index: 0 },
      ],
    };
  }

  // Perfect-information default: every seat sees the full state. Implement
  // this for hidden-info games (reveal only each seat's slice), and use
  // `args.cause` (the move/event that produced this state, null for the
  // initial frame) to embed per-seat animation cues — e.g. a `lastMove`
  // field — into the slice.
  computeObservation = passthroughObservation<State, Action, Config>;

  // Predicate hooks — replace with your game's rules, and keep them in sync
  // with the Dart `GameRules` twins for this version. This example rates
  // nothing and seats every bot.
  ratingPool(_args: RatingPoolArgs<Config>): string | null {
    return null;
  }

  botSeatable(_args: BotSeatableArgs<Config>): boolean {
    return true;
  }
}

/** The v1 rules unit, registered under key `1` in `game.ts`. */
export const rulesV1: GameRules = new ExampleRulesV1();
