/**
 * App gameEngine — the single seam you own in the `game` edge function.
 *
 * Implement your game's {@link GameEngine} here and export it as `gameEngine`.
 * The engine-owned harness ({@link ../engine/index.ts}) imports this instance and
 * serves it; you never touch the routing, auth, gated reads, or commits. All
 * six game hooks that used to be PL/pgSQL — the four heavy ones
 * (`game_initial_state`, `game_apply_action`, `game_handle_system_action`,
 * `game_compute_observation`) and the two predicates (`game_rating_pool`,
 * `game_bot_seatable`) — live here now as TypeScript. The predicate twins also
 * exist in the Dart `GameModule` for client UX (the create dialog's rating
 * toggle, bot-picker filtering); keep the two languages in sync (this side is
 * authoritative).
 *
 * ## Payload typing — schema-first
 *
 * Declare a Zod schema per payload (`state`, `action`, `config`) and derive
 * the types with `z.infer` — the schema is the single source of truth. The
 * engine harness parses every payload with the game row's `schema_version`
 * entry from {@link GameEngine.schemas} before invoking a hook, so hook bodies
 * receive validated, typed values (never raw JSON), and it re-validates the
 * state a hook returns before committing it. Conventions:
 *
 * - Derive payload types as `type` aliases via `z.infer` (an `interface`
 *   fails the engine's `JsonObject` constraint).
 * - Keep schemas transform-free: what parses is what persists, and the
 *   harness validates hook output against the same `state` schema.
 * - Ship one `schemas` entry per `schema_version` you support. On a breaking
 *   shape change, add an entry (games created before keep parsing under
 *   theirs) and make the payload type the tagged union of the versions'
 *   shapes so hooks can narrow.
 *
 * `dart run eigen_engine:sync_supabase` scaffolds this file once from the
 * engine example and then **never overwrites it** — it is yours to edit
 * (unlike `index.ts`/`deno.json`, which the engine owns and re-vendors every
 * sync).
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
  GameEngine,
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

class ExampleEngine implements GameEngine<State, Action, Config> {
  readonly schemas = {
    1: { state: stateSchema, action: actionSchema, config: configSchema },
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

  // Perfect-information default: every seat sees the full state. Implement this
  // for hidden-info games (reveal only each seat's slice).
  computeObservation = passthroughObservation<State, Config>;

  // Predicate hooks — replace with your game's rules. This example rates every
  // multi-setting game in one 'casual' pool and seats every bot.
  ratingPool(_args: RatingPoolArgs<Config>): string | null {
    return null;
  }

  botSeatable(_args: BotSeatableArgs<Config>): boolean {
    return true;
  }
}

/** The app's gameEngine instance, served by the engine harness in `index.ts`.
 * The bare `GameEngine` annotation is the deliberate seam: it type-checks the
 * concrete engine against the contract the harness consumes. */
export const gameEngine: GameEngine = new ExampleEngine();
