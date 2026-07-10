import type { Rating } from "openskill";
import type Rand from "rand-seed";
import type { ZodType } from "zod";
import type { Database as DatabaseGenerated, Json } from "./database.types.ts";

// ── Database ──────────────────────────────────────────────────────────────────

/** The generated RPC signatures, the base the {@link Database} overrides merge
 * into. */
type GeneratedFunctions = DatabaseGenerated["public"]["Functions"];

/** One RPC signature with corrected `Args`: the overriding fields replace their
 * generated counterparts; everything else (remaining args, `Returns`) is kept.
 * Deliberately shallow `Omit`/`&` composition — a recursive deep-merge (e.g.
 * type-fest's `MergeDeep`) re-expands the whole generated schema every time
 * `Database` is related, which pushes the Hono chained-route app types over
 * TypeScript's instantiation-depth limit (TS2589). */
type OverrideArgs<
  Name extends keyof GeneratedFunctions,
  NewArgs extends Record<string, unknown>,
> = Omit<GeneratedFunctions[Name], "Args"> & {
  Args: Omit<GeneratedFunctions[Name]["Args"], keyof NewArgs> & NewArgs;
};

/**
 * The engine's working `Database` type: the generated schema with the
 * engine-owned RPC `Args` corrected. Import `Database` from here, never from
 * `database.types.ts` — the merged type is what makes `db.rpc(...)` calls
 * check against the real wire shapes with no casts. (This module is the
 * generated file's only importer.)
 *
 * The generator has two blind spots the overrides fix:
 *   - nullable SQL function args are emitted as bare `number`/`string`;
 *   - `jsonb` args are emitted as opaque `Json`.
 * Only *engine-owned* wire shapes are overridden — the engine owns both sides
 * of these RPCs, so the TS types here and the SQL contract move together.
 * Game-owned jsonb (`games.config`, `game_states.state`, `observations.data`)
 * deliberately stays `Json`: the per-game schema boundary
 * ({@link GameRules.schemas}) types those, never the engine.
 */
export type Database = Omit<DatabaseGenerated, "public"> & {
  public: Omit<DatabaseGenerated["public"], "Functions"> & {
    Functions:
      & Omit<
        GeneratedFunctions,
        | "engine_commit_action"
        | "engine_commit_start"
        | "engine_create_game"
        | "engine_create_solo_game"
      >
      & {
        /** One state transition. `p_caller_id` is the acting human (verified
         * `auth.uid()`), null for bot/system; `p_acting_bot_id` the acting
         * bot, null for user/system. `p_expected_version` keeps the generated
         * non-null `number`: every mode sends the version the transition was
         * computed against — a stale race then rejects (user/bot), retries
         * (resign/forfeit), or abstains (timeout). `p_transitions` is always
         * length 1 (a timeout resolves the whole pending set in one
         * transition); it stays an array to match the SQL JSONB arg shape. */
        engine_commit_action: OverrideArgs<
          "engine_commit_action",
          {
            p_mode: CommitMode;
            p_caller_id: string | null;
            p_acting_bot_id: string | null;
            p_transitions: CommitTransitionWire[];
          }
        >;
        /** Idempotent start commit (no-op if already active; creator-only via
         * `p_caller_id`). `p_seed` is the game's base RNG seed — an opaque
         * random string written to the v0 state row and copied onto every
         * later row by the commit RPC. */
        engine_commit_start: OverrideArgs<
          "engine_commit_start",
          {
            p_initial_state: JsonObject;
            p_observations: SeatObservationWire[];
            p_pending: number[];
            p_turn_seconds: number | null;
          }
        >;
        /** `p_pool` is the EF's TS-computed rating pool (null ⇒ unrated);
         * `p_config` has already been parsed against the requested version's
         * config schema. */
        engine_create_game: OverrideArgs<
          "engine_create_game",
          {
            p_config: JsonObject;
            p_pool: string | null;
            p_turn_seconds: number | null;
            p_budget_seconds: number | null;
            p_increment_seconds: number | null;
          }
        >;
        engine_create_solo_game: OverrideArgs<
          "engine_create_solo_game",
          {
            p_config: JsonObject;
            p_turn_seconds: number | null;
            p_budget_seconds: number | null;
            p_increment_seconds: number | null;
          }
        >;
      };
  };
};

// ── Core JSON ─────────────────────────────────────────────────────────────────

/** A JSON object — the shape of `state`, `config`, `data`, and observation
 * slices, and the constraint every game payload type must satisfy. Matches the
 * generated {@link Json} object branch (including `undefined` values, so
 * optional properties in `z.infer` payload types are assignable — declare those
 * payloads as `type` aliases, not `interface`s, or the implicit index signature
 * this constraint relies on is lost). */
export type JsonObject = { [key: string]: Json | undefined };

/** Re-exported so engine modules can annotate raw `jsonb` RPC results without
 * importing the generated file directly (this module stays its only importer).
 * An explicit `Json` return annotation also caps the inference chain that the
 * TS2589 note above is about. */
export type { Json };

// ── DB-derived enums ──────────────────────────────────────────────────────────

/** The trigger of a lifecycle action, resolved by the game's `applyLifecycle`
 * hook — the DB `lifecycle_type` enum (which has no table column; it is
 * logged inside the action's `data`). `forfeit` is a voluntary resign;
 * `auto_forfeit` the engine-driven variant (account-deletion purge);
 * `timeout` is the clock. The two forfeits share a shape (both target
 * `data.player_index`) and most games resolve them identically — but the
 * hook receives the real trigger, so a game may choose different
 * consequences (e.g. a draw rather than a loss when the seat was purged). */
export type LifecycleType = Database["public"]["Enums"]["lifecycle_type"];

/** Per-player result — the DB `game_result` enum. */
export type GameResult = Database["public"]["Enums"]["game_result"];

/** Game visibility — the DB `game_access` enum (`public`/`private`/`friends`). */
export type GameAccess = Database["public"]["Enums"]["game_access"];

/** Who performed a logged action — the DB `action_type` enum. */
export type ActionType = Database["public"]["Enums"]["action_type"];

/** Which species a logged action is — the DB `action_kind` enum. Everything
 * that transitions state is an *action*; the two species differ by contract:
 * a `game` action is rules-scoped (game-defined payload, validated by
 * `applyAction`, rejectable as illegal), a `lifecycle` action is
 * engine-scoped (a {@link LifecycleAction} payload, resolved unconditionally
 * by `applyLifecycle`). Stamped on every `actions` row at commit time, so
 * replay classifies the log by column, never by payload shape. */
export type ActionKind = Database["public"]["Enums"]["action_kind"];

// ── Game outcome / envelope / observation ─────────────────────────────────────

/**
 * One participant's result, written to `game_outcomes` when the game ends.
 * `placement` (1 = best, ties share a value) feeds OpenSkill directly;
 * `team_index` groups players rated together (use `player_index` for individual
 * games). See engine_architecture.md §8.
 */
export interface OutcomeEntry {
  player_index: number;
  result: GameResult;
  placement: number;
  team_index: number;
  /** Optional raw game score, for display or score-based variants. */
  score?: number | null;
}

/**
 * The result of advancing the game by one transition — the return of
 * `initialState`, `applyAction`, and `applyLifecycle`. Mirrors the SQL hook
 * envelope.
 */
export interface Envelope<TState extends JsonObject = JsonObject> {
  /** New pure game payload (board, deck, fog…). Never carries whose-turn or
   * winner info — those are infra columns. Must match the game's
   * `schema_version` schema — the harness validates it before committing. */
  state: TState;
  /** 0-based seats that may act next. Empty ⇒ game over. */
  pending_players: number[];
  /** Present **only** when the game ends. Absent/undefined means ongoing —
   * infra treats it as SQL NULL. */
  outcome?: OutcomeEntry[];
  /** Optional per-action deadline override for *this action only* (does not
   * touch any player's bank). Omit to use the game's configured timing. */
  turn_seconds?: number;
}

/** One participant's view of the state, produced by `computeObservation`. */
export interface ObservationSlice {
  /** What this seat is permitted to see. */
  data: JsonObject;
  /** Pending set as this seat sees it — may be narrowed from the true set for
   * hidden-info games (e.g. a Nope window). */
  pending_players: number[];
}

// ── GameModule hook args + contract ───────────────────────────────────────────

/** Args common to every hook: the game config, parsed by the harness against
 * the version schema of the {@link GameRules} entry being invoked. No
 * `schemaVersion` field — a rules unit is version-specific by construction,
 * so hooks never branch on version. */
interface HookContext<TConfig extends JsonObject = JsonObject> {
  config: TConfig;
}

export interface InitialStateArgs<TConfig extends JsonObject = JsonObject>
  extends HookContext<TConfig> {
  /** Deterministic RNG for this transition, derived by the harness from the
   * game's stored base seed and the state version this envelope commits as.
   * Draw freely (`rng.next()` → float in `[0, 1)`, stateful within the
   * invocation); replaying the transition re-derives the identical sequence,
   * so the game stays a pure function of (base seed, action log) — provided
   * the hook draws in deterministic code order. */
  rng: Rand;
  playerCount: number;
}

export interface ApplyActionArgs<
  TState extends JsonObject = JsonObject,
  TAction extends JsonObject = JsonObject,
  TConfig extends JsonObject = JsonObject,
> extends HookContext<TConfig> {
  state: TState;
  pending: number[];
  data: TAction;
  playerIndex: number;
  /** Deterministic per-transition RNG — see {@link InitialStateArgs.rng}. */
  rng: Rand;
}

/** The infra-constructed payload of a lifecycle action, recorded verbatim in
 * the `actions` log (with `kind = 'lifecycle'`). Engine-owned and
 * version-independent: every game gets these transitions for free, without
 * declaring them in its schemas. `forfeit` carries the forfeiting seat (a
 * voluntary resign); `auto_forfeit` is the engine-driven variant (account
 * purge); `timeout` carries no seat — the affected seats are
 * {@link ApplyLifecycleArgs.pending}. */
export type LifecycleAction =
  | { type: "timeout" }
  | { type: "forfeit" | "auto_forfeit"; player_index: number };

export interface ApplyLifecycleArgs<
  TState extends JsonObject = JsonObject,
  TConfig extends JsonObject = JsonObject,
> extends HookContext<TConfig> {
  state: TState;
  /** Seats awaiting an action. For `timeout` these are exactly the seats that
   * ran out of time — resolve the whole set in one envelope (you may declare a
   * draw). For `forfeit`/`auto_forfeit`, the target seat is in
   * `data.player_index`. */
  pending: number[];
  /** The trigger — always equal to `data.type`. */
  type: LifecycleType;
  data: LifecycleAction;
  /** Deterministic per-transition RNG — see {@link InitialStateArgs.rng}. */
  rng: Rand;
}

/**
 * The action that produced the state being projected — a `game` action
 * (`applyAction`), a `lifecycle` action (`applyLifecycle`), or `null` for
 * the initial frame (`initialState`), which no action produced. The `kind`
 * discriminator matches the `actions.kind` column.
 *
 * This is how a game tells each seat *what happened* — pure frame diffing
 * can't recover causality (identical footprints, hidden-info moves, composite
 * resolutions). Embed whatever animation/narration cues a seat is permitted
 * to see into that seat's slice `data` (e.g. a `lastMove` field); visibility
 * stays game-controlled because the embedding happens inside
 * `computeObservation`. Cues describe a *transition*: a client should render
 * them as animation only when it has the frame's predecessor, and as static
 * "last move" info otherwise.
 */
export type TransitionCause<TAction extends JsonObject = JsonObject> =
  | { kind: "game"; data: TAction; playerIndex: number }
  | { kind: "lifecycle"; data: LifecycleAction }
  | null;

export interface ComputeObservationArgs<
  TState extends JsonObject = JsonObject,
  TAction extends JsonObject = JsonObject,
  TConfig extends JsonObject = JsonObject,
> extends HookContext<TConfig> {
  state: TState;
  pending: number[];
  playerIndex: number;
  participantCount: number;
  /** What produced `state` — see {@link TransitionCause}. Shared across the
   * per-seat fan-out; per-seat filtering of what it reveals is this hook's
   * job. */
  cause: TransitionCause<TAction>;
  /** TRUE only when projecting a finished game for replay — hidden-info games
   * may reveal opponent state. */
  isReplay: boolean;
}

/** The chosen game settings, passed to {@link GameRules.ratingPool} at creation
 * so the game can decide its rating pool (or that the game is unrated). Mirrors
 * the columns `create_game` writes; `config` is already parsed against the
 * requested version's config schema. */
export interface RatingPoolArgs<TConfig extends JsonObject = JsonObject> {
  access: GameAccess;
  turnSeconds: number | null;
  budgetSeconds: number | null;
  incrementSeconds: number | null;
  minPlayers: number;
  maxPlayers: number;
  config: TConfig;
}

/** A candidate bot seating, passed to {@link GameRules.botSeatable}.
 * `gameConfig` is parsed against the game's version schema; `botConfig` is the
 * bot's declared capabilities (`bots.config`) — game-owned but unversioned by
 * the game schemas, so it stays opaque. */
export interface BotSeatableArgs<TConfig extends JsonObject = JsonObject> {
  gameConfig: TConfig;
  botConfig: JsonObject;
}

/** The declarative payload contracts for one `schema_version`: the Zod schemas
 * the harness uses to parse (and validate) every game payload crossing the
 * jsonb boundary. Keep them transform-free — what parses is what persists, and
 * the harness re-validates hook-returned state against `state`. */
export interface GameSchemas<
  TState extends JsonObject = JsonObject,
  TAction extends JsonObject = JsonObject,
  TConfig extends JsonObject = JsonObject,
> {
  /** The pure game payload stored in `game_states.state`. */
  state: ZodType<TState>;
  /** A player move's `data`, as submitted by clients and bots. */
  action: ZodType<TAction>;
  /** The per-instance creation config stored in `games.config`. */
  config: ZodType<TConfig>;
}

/**
 * Everything one `schema_version` of a game needs: the payload contracts plus
 * all six hooks, narrowly typed to that version's shapes. The Dart client has
 * a same-named `GameRules` twin (its unit holds the client-side surface —
 * payload codec, `isValidAction`/`previewAction`, rendering, and the
 * `ratingPool`/`botSeatable` twins); keep the two in sync per version.
 *
 * The type parameters are the version's payload types, inferred from the Zod
 * schemas in {@link schemas} (`z.infer<typeof stateSchema>` etc. — use `type`
 * aliases, not `interface`s). The harness parses every payload with this
 * unit's schemas before invoking its hooks, so hook bodies never see
 * unvalidated JSON — and never another version's shape. When rules or shapes
 * change incompatibly, ship a new `GameRules` under the next version key
 * (reusing unchanged pieces by import) instead of branching inside hooks.
 */
export interface GameRules<
  TState extends JsonObject = JsonObject,
  TAction extends JsonObject = JsonObject,
  TConfig extends JsonObject = JsonObject,
> {
  /** The payload contracts for this version. */
  schemas: GameSchemas<TState, TAction, TConfig>;

  /** Starting envelope. Draw any setup randomness (deck shuffle, first
   * player…) from `args.rng`. */
  initialState(args: InitialStateArgs<TConfig>): Envelope<TState>;

  /** Apply a player's move. The infra has already confirmed it is this seat's
   * turn at the expected version, so do not re-check turn order — only validate
   * move legality and throw `IllegalMoveError` (from `_engine/game-engine.ts`)
   * if it fails; the harness renders it as a 400. Any other throw is a bug and
   * surfaces as a 500. */
  applyAction(
    args: ApplyActionArgs<TState, TAction, TConfig>,
  ): Envelope<TState>;

  /** Resolve a lifecycle action (`forfeit`/`timeout`) into an envelope.
   * Lifecycle actions operate on the game from outside its rules — they may
   * be player-triggered (a resign) or engine-triggered (timeout, purge);
   * either way the consequence is the game's to decide. Unlike `applyAction`
   * it cannot be "illegal" — it always resolves. */
  applyLifecycle(args: ApplyLifecycleArgs<TState, TConfig>): Envelope<TState>;

  /** Project the state into one seat's view — including what that seat may
   * see of the transition that produced it (`args.cause`), so the client can
   * animate. Perfect-info games can use the `passthroughObservation` helper
   * (which ignores the cause). */
  computeObservation(
    args: ComputeObservationArgs<TState, TAction, TConfig>,
  ): ObservationSlice;

  /** Decide whether — and in which pool — a game with these settings is rated.
   * Return the pool name (e.g. `'rapid'`) or `null` for unrated. The EF computes
   * `canBeRated = pool != null && !guest` and validates the client's concrete
   * `rated` assertion against it (rejecting a mismatch), then writes it via
   * `engine_create_game`. The Dart `GameRules` keeps a twin of this so the
   * create dialog can gate the Rated/Casual toggle and send the same value. */
  ratingPool(args: RatingPoolArgs<TConfig>): string | null;

  /** Decide whether a bot's declared capabilities (`botConfig`) support a game
   * with `gameConfig`. The EF gates seating on this before committing; the Dart
   * `GameRules` twin filters the bot pickers locally. Return `true` to allow. */
  botSeatable(args: BotSeatableArgs<TConfig>): boolean;
}

/**
 * The complete game-specific surface — the same-named twin of the Dart
 * `GameModule` (whose extras are client-only creation/about UI). Implement
 * this once per app in `functions/_lib/game.ts` (replace the scaffolded
 * example) and export the instance as `gameModule`; the engine-owned
 * harnesses pass it to `createEngineApp`. The authoring helpers
 * (`IllegalMoveError`, `passthroughObservation`) live in
 * `_engine/game-engine.ts`.
 *
 * The harness owns all version dispatch: every request resolves the game
 * row's `schema_version` entry from {@link versions} and invokes that unit's
 * hooks — game code never branches on version.
 */
export interface GameModule {
  /** The {@link GameRules} units keyed by `schema_version` — exactly the
   * versions this build ships. Sparse on purpose: game creation rejects a
   * version not present here, loading a stored game requires its version's
   * entry, and a drained old version is retired by deleting its entry. The
   * entries erase to bare `GameRules` — safe, because the harness parses each
   * payload with the same entry's schemas before invoking its hooks. */
  versions: Record<number, GameRules>;
}

// ── Ratings ───────────────────────────────────────────────────────────────────

/** OpenSkill Gaussian rating parameters (`mu`, `sigma`) — openskill's own
 * type, re-exported (type-only, erased at runtime) so the seat/wire types
 * below can never drift from what `rate()` consumes and produces. */
export type { Rating };

/** A player seat to be rated.
 *
 * Self-contained: each seat's current `mu`/`sigma` is bundled, so the rating
 * module never reads the database. `display_rating` is intentionally NOT carried
 * — it is derived from `mu`/`sigma` so the formula lives in one place per side of
 * the wire. */
export interface PlayerInput extends Rating {
  player_index: number;
  user_id: string | null;
  bot_id: string | null;
  /** Ordinal finish rank (1 = best); ties share the same value. */
  placement: number;
  /** Players sharing a team_index are rated as one team. For individual games
   * this equals player_index. */
  team_index: number;
}

/** One identity's newly computed rating — the pure OpenSkill posterior, before
 * the infra-owned `expected_revision` is attached (see {@link RatingWrite}). */
export interface RatingResult extends Rating {
  identity: { user_id: string } | { bot_id: string };
}

/** One identity's rating write — the contract consumed by the commit RPC's
 * in-transaction rating writer.
 *
 * Carries only the new `(mu, sigma)` plus `expected_revision` (the
 * `player_ratings.revision` the EF read). The commit applies it under an
 * optimistic compare-and-swap on that revision; `display_rating` is derived in
 * SQL from `(mu, sigma)` and the `before` snapshot is captured by SQL from the
 * row being overwritten — a revision match proves that row is the baseline this
 * `mu/sigma` was computed from. `expected_revision = 0` means the identity has no
 * rating row yet (computed from the OpenSkill defaults). */
export interface RatingWrite extends RatingResult {
  expected_revision: number;
}

// ── EF ⇄ SQL wire: reads ──────────────────────────────────────────────────────
// The read views (game-state, for-start, ratings, replay) are not declared here:
// they are *inferred* from their typed-SDK mappers in `_engine/repo.ts` and
// exported there (`ReadGameState`, `Seat`). Only the `*Wire` payload types
// below stay hand-declared — they are the jsonb shapes the commit RPCs consume,
// wired into the RPC `Args` by the {@link Database} override at the top of this
// module (so the RPC calls themselves need no param interfaces or casts).

// ── EF ⇄ SQL wire: commits ────────────────────────────────────────────────────

/** A seat's computed observation for the commit wire: an {@link ObservationSlice}
 * tagged with its seat (the commit RPC stamps `version` + timing columns). */
export type SeatObservationWire = ObservationSlice & { player_index: number };

/** A single state transition to persist. Every commit sends exactly one — a
 * timeout resolves the whole pending set in one holistic transition. */
export interface CommitTransitionWire {
  /** Recorded in the `actions` log (e.g. the move, or `{type, player_index}`). */
  action_data: JsonObject;
  new_state: JsonObject;
  new_pending: number[];
  /** Per-player results when this transition ends the game, else null. */
  outcome: OutcomeEntry[] | null;
  /** Per-action deadline override, else null. */
  turn_seconds: number | null;
  /** Performer's seat. Null for all identity-less system actions (timeout,
   * engine-driven forfeit); set for user/bot moves and a user resign. */
  player_index: number | null;
  observations: SeatObservationWire[];
  /** OpenSkill updates to write atomically with the finish; null for ongoing
   * moves and unrated games. Only a finishing transition carries these. */
  rating_updates: RatingWrite[] | null;
}

export type CommitMode = "user" | "bot" | "resign" | "forfeit" | "timeout";

// ── Infra payloads ────────────────────────────────────────────────────────────
/** Return of `engine_send_friend_request` — what the social EF needs to address
 * a push. `notify_user_id` is the target in both notify cases, else null. */
export interface SendFriendResult {
  created_pending: boolean;
  auto_accepted: boolean;
  notify_user_id: string | null;
  actor_display_name: string | null;
}

/** Return of `engine_accept_friend_request` — notify the original `requester_id`
 * that `accepter_display_name` accepted, when `accepted` is true. */
export interface AcceptFriendResult {
  accepted: boolean;
  requester_id: string | null;
  accepter_display_name: string | null;
}

/** One frame of a finished game's replay — the `/engine/game/replay` response
 * entry.
 *
 * The game-defined payloads (`data`, `action_data`) are deliberately `unknown`,
 * not the recursive `Json`: they are opaque to the engine — only the game's
 * schema for the row's `schema_version` gives them shape, on whichever side
 * consumes them — and a recursive type in a response would also blow up Hono's
 * typed-response inference (TS2589). */
export interface ReplayFrame {
  version: number;
  /** The caller's observation slice for this frame (game-defined). */
  data: unknown;
  pending_players: number[];
  created_at: string;
  /** Who performed the action producing this frame; null for the initial
   * frame, which no action produced. */
  action_type: ActionType | null;
  /** Which species produced this frame (`game` or `lifecycle`); null for the
   * initial frame. */
  action_kind: ActionKind | null;
  /** The action payload as logged (game-defined for `kind = 'game'`, a
   * {@link LifecycleAction} for `kind = 'lifecycle'`). */
  action_data: unknown;
  /** Performer's seat; null for identity-less system actions — a timeout's
   * affected seats come from the pending diff, not this column. */
  action_player_index: number | null;
}
