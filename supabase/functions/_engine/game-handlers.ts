/**
 * Request-body schemas and handlers for the engine's client-facing game group
 * (`/engine/game/*`).
 *
 * Routes are registered in `app.ts`; every one requires a verified user JWT
 * (`auth: 'user'`). Each request body is declared as a Zod schema next to its
 * handlers, so handlers receive parsed, typed input; game-defined fields
 * (`config`, a move's `data`) stay open here and are typed by the game's own
 * schema boundary (`parseClientPayload`). Handlers read `supabaseAdmin` and
 * `userClaims` directly from the typed Hono context, and their `c.json(...)`
 * return types are deliberately inferred so each response shape flows into the
 * `EngineApp` type `app.ts` exports.
 *
 * The state-transitioning routes delegate to the shared pipeline in
 * `game-pipeline.ts`.
 */

import type { Context } from "@hono/hono";
import type {
  GameModule,
  GameRules,
  ReplayFrame,
  TransitionCause,
} from "types/engine.types.ts";
import { z } from "zod";
import {
  assertBudgetPending,
  assertHookState,
  parseClientPayload,
  parseStoredPayload,
  rulesFor,
} from "./game-engine.ts";
import {
  applyGameAction,
  assertLocalBotSeat,
  expireGame,
  forfeitGame,
  purgeUserGames,
  seatOf,
} from "./game-pipeline.ts";
import { notifyGameInvite, notifyGameStarted } from "./notify.ts";
import { deriveRng, fanOutObservations, randomSeed } from "./observation.ts";
import {
  addBotToGame,
  commitStart,
  createGame,
  createSoloGame,
  readBots,
  readForStart,
  readGameConfig,
  readGameState,
  readReplay,
} from "./repo.ts";
import {
  type AppEnv,
  EngineCode,
  HttpError,
  requireUserId,
} from "./runtime.ts";

// ── Request bodies ────────────────────────────────────────────────────────────
// One Zod schema per route; `jsonBody` parses and 400s in the engine error
// shape. `config` / `data` are game-defined, so they stay open here — the
// game's `schemas` entry types them at the schema boundary.

const timingFields = {
  turn_seconds: z.number().int().nullable().default(null),
  budget_seconds: z.number().int().nullable().default(null),
  increment_seconds: z.number().int().nullable().default(null),
};

type TimingBody = {
  turn_seconds: number | null;
  budget_seconds: number | null;
  increment_seconds: number | null;
};

// The two timing-model rules shared by game and solo creation. These are also
// `games` CHECK constraints (`timing_mode_exclusive`,
// `increment_requires_budget`); the schema owns the friendly error, the
// constraints remain the drift-proof backstop.
const timingExclusive = (v: TimingBody) =>
  v.turn_seconds === null || v.budget_seconds === null;
const incrementNeedsBudget = (v: TimingBody) =>
  v.increment_seconds === null || v.budget_seconds !== null;

export const createBody = z
  .object({
    access: z.enum(["public", "private", "friends"]).default("public"),
    schema_version: z.number().int(),
    config: z.record(z.string(), z.unknown()).default({}),
    min_players: z.number().int().min(1),
    max_players: z.number().int().min(1),
    rated: z.boolean().optional(),
    ...timingFields,
  })
  .refine(
    timingExclusive,
    "turn_seconds and budget_seconds are mutually exclusive",
  )
  .refine(incrementNeedsBudget, "increment_seconds requires budget_seconds")
  .refine(
    (v) => v.max_players >= v.min_players,
    "max_players must be at least min_players",
  );

export const createSoloBody = z
  .object({
    bot_ids: z.array(z.string()).min(1, "A solo game needs at least one bot"),
    schema_version: z.number().int(),
    config: z.record(z.string(), z.unknown()).default({}),
    ...timingFields,
  })
  .refine(
    timingExclusive,
    "turn_seconds and budget_seconds are mutually exclusive",
  )
  .refine(incrementNeedsBudget, "increment_seconds requires budget_seconds");

export const gameIdBody = z.object({ game_id: z.string() });

export const addBotBody = z.object({ game_id: z.string(), bot_id: z.string() });

export const actionBody = z.object({
  game_id: z.string(),
  data: z.unknown(),
  expected_version: z.number().int(),
});

export const localBotActionBody = actionBody.extend({
  player_index: z.number().int().min(0),
});

// ── Route handlers ────────────────────────────────────────────────────────────

export async function handleAction(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof actionBody>,
) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  // The caller's own committed frame rides the response as a latency shortcut:
  // the client feeds it into the same version-deduped observation pipeline the
  // Realtime events flow through, which then drops the duplicate event.
  const observation = await applyGameAction(gameModule, db, {
    gameId: body.game_id,
    data: body.data,
    expectedVersion: body.expected_version,
    mode: "user",
    resolve: (read) => ({
      playerIndex: seatOf(read, userId),
      callerId: userId,
      botId: null,
    }),
  });
  return c.json({ ok: true, observation });
}

export async function handleStart(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof gameIdBody>,
) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  const start = await readForStart(db, body.game_id);
  // Non-authoritative fast-fail (the commit RPC re-checks the creator under
  // its lock): without it, anyone holding a game id could burn hook +
  // fan-out compute on a request that is guaranteed to be rejected.
  if (start.created_by !== userId) {
    throw new HttpError(403, "Only the game creator can start the game");
  }
  const rules = rulesFor(gameModule, start.schema_version);
  const config = parseStoredPayload(
    rules.schemas.config,
    start.config,
    "config",
    start.schema_version,
  );

  const seed = randomSeed();
  const envelope = rules.initialState({
    rng: deriveRng(seed, 0),
    config,
    playerCount: start.player_count,
  });
  assertHookState(rules.schemas, envelope, start.schema_version);
  assertBudgetPending(start.budget_seconds, envelope, start.schema_version);
  const observations = fanOutObservations(rules, {
    state: envelope.state,
    pending: envelope.pending_players,
    participantCount: start.player_count,
    config,
    cause: null,
    isReplay: false,
  });

  await commitStart(db, {
    p_caller_id: userId,
    p_game_id: body.game_id,
    p_initial_state: envelope.state,
    p_pending: envelope.pending_players,
    p_seed: seed,
    p_turn_seconds: envelope.turn_seconds ?? null,
    p_observations: observations,
  });
  EdgeRuntime.waitUntil(
    notifyGameStarted(db, body.game_id, envelope.pending_players),
  );
  return c.json({ ok: true });
}

/** Create a game. The EF is authoritative for policy: it validates the request,
 * gates guests, derives the rating pool, and validates the client's `rated`
 * assertion — the gated RPC is a thin writer backed by the `games` CHECK
 * constraints. A friends invite is pushed post-commit. */
export async function handleCreate(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof createBody>,
) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  const isAnon = c.var.supabaseContext.jwtClaims?.is_anonymous === true;

  // Guests cannot create friends-access games: every social RPC rejects guests,
  // so a guest can never have an accepted friend to join — the lobby would be
  // permanently unjoinable.
  if (body.access === "friends" && isAnon) {
    throw new HttpError(
      403,
      "Friends-access games require a registered account",
    );
  }

  // The client's schema_version must be one this deployment ships rules for
  // (an older app creating an older-version game is fine); the config is
  // parsed with that version's schema before anything is persisted.
  const rules = rulesFor(gameModule, body.schema_version, 400);
  const config = parseClientPayload(
    rules.schemas.config,
    body.config,
    "config",
  );

  const pool = rules.ratingPool({
    access: body.access,
    turnSeconds: body.turn_seconds,
    budgetSeconds: body.budget_seconds,
    incrementSeconds: body.increment_seconds,
    minPlayers: body.min_players,
    maxPlayers: body.max_players,
    config,
  });

  // `rated` is a determined value the client also computes (the Dart twin of the
  // rating rules) and sends as a concrete assertion — not a preference. Validate
  // it against the server's computation and reject a mismatch (Dart↔TS logic
  // drift, or a forged client) rather than silently coercing. The only outcomes
  // are forced-unrated (ineligible pool or guest) and toggle (eligible) — there
  // is no forced-rated, so a sent `false` is always valid.
  const canBeRated = pool !== null && !isAnon;
  if (!canBeRated && body.rated === true) {
    throw new HttpError(
      422,
      "rated mismatch: this game is not eligible to be rated",
    );
  }
  const rated = canBeRated && (body.rated ?? true);

  const gameId = await createGame(db, {
    p_caller_id: userId,
    p_min_players: body.min_players,
    p_max_players: body.max_players,
    p_schema_version: body.schema_version,
    p_access: body.access,
    p_turn_seconds: body.turn_seconds,
    p_budget_seconds: body.budget_seconds,
    p_increment_seconds: body.increment_seconds,
    p_config: config,
    p_rated: rated,
    p_pool: pool,
  });

  if (body.access === "friends") {
    EdgeRuntime.waitUntil(notifyGameInvite(db, gameId));
  }
  return c.json({ game_id: gameId });
}

/** Create a sole-human "Play vs AI" game. The EF owns the bot-class policy
 * (seatability, schema, guest/server, timing rules); the gated RPC just seats
 * the bots atomically. The client calls `/game/start` next. */
export async function handleCreateSolo(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof createSoloBody>,
) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  const isAnon = c.var.supabaseContext.jwtClaims?.is_anonymous === true;

  const rules = rulesFor(gameModule, body.schema_version, 400);
  const config = parseClientPayload(
    rules.schemas.config,
    body.config,
    "config",
  );
  const timed = body.turn_seconds !== null || body.budget_seconds !== null;

  const bots = await readBots(db, body.bot_ids);
  let hasServer = false;
  let hasLocal = false;
  for (const botId of body.bot_ids) {
    const bot = bots.get(botId);
    if (bot === undefined) throw new HttpError(404, `Bot not found: ${botId}`);
    if (body.schema_version > bot.schemaVersion) {
      throw new HttpError(
        400,
        `Bot ${botId} does not support schema ${body.schema_version}`,
      );
    }
    if (!rules.botSeatable({ gameConfig: config, botConfig: bot.config })) {
      throw new HttpError(400, "Bot does not support this game configuration");
    }
    if (bot.isLocal) {
      hasLocal = true;
    } else {
      hasServer = true;
      if (isAnon) {
        throw new HttpError(403, "Guests can only play against local bots");
      }
    }
  }

  // Timing is a turn-deadline backstop for an actor that might not respond. A
  // server bot needs one (its endpoint may be unreachable); a local bot is driven
  // by the present human's client and must not be subject to a deadline it can
  // miss merely because the human navigated away. These rules also forbid mixing
  // the two bot classes in one game.
  if (hasServer && !timed) {
    throw new HttpError(400, "A solo game with a server bot must be timed");
  }
  if (hasLocal && timed) {
    throw new HttpError(400, "A solo game with a local bot must be untimed");
  }

  const gameId = await createSoloGame(db, {
    p_caller_id: userId,
    p_bot_ids: body.bot_ids,
    p_schema_version: body.schema_version,
    p_turn_seconds: body.turn_seconds,
    p_budget_seconds: body.budget_seconds,
    p_increment_seconds: body.increment_seconds,
    p_config: config,
  });
  return c.json({ game_id: gameId });
}

/** Host-only "Add bot" in a waiting room. Guests are rejected here (server bots
 * cost per-move compute); the gated RPC enforces the creator + seat-count
 * invariants under its lock. */
export async function handleAddBot(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof addBotBody>,
) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  if (c.var.supabaseContext.jwtClaims?.is_anonymous === true) {
    throw new HttpError(403, "Guests cannot add server bots");
  }
  // The game-config and bot reads are independent — fetch them concurrently so
  // the route is one read round-trip + the write, not two sequential reads.
  const [game, bots] = await Promise.all([
    readGameConfig(db, body.game_id),
    readBots(db, [body.bot_id]),
  ]);
  const bot = bots.get(body.bot_id);
  if (bot === undefined) throw new HttpError(404, "Bot not found");
  // Same backstop rationale as create-solo: a server bot's endpoint may be
  // unreachable, and the expiry sweep is the retry for a lost wake — which
  // only exists when the game has a turn deadline. This route seats server
  // bots exclusively, so the game must be timed.
  if (game.turn_seconds === null && game.budget_seconds === null) {
    throw new HttpError(400, "A game with a server bot must be timed");
  }
  const rules = rulesFor(gameModule, game.schema_version);
  const gameConfig = parseStoredPayload(
    rules.schemas.config,
    game.config,
    "config",
    game.schema_version,
  );
  if (!rules.botSeatable({ gameConfig, botConfig: bot.config })) {
    throw new HttpError(400, "Bot does not support this game configuration");
  }
  await addBotToGame(db, userId, body.game_id, body.bot_id);
  return c.json({ ok: true });
}

export async function handleForfeit(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof gameIdBody>,
) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  await forfeitGame(gameModule, db, body.game_id, userId, "resign");
  return c.json({ ok: true });
}

/** An authenticated participant nudges their own expired game (the cron sweep
 * in `internal-handlers.ts` is the batch driver). */
export async function handleExpireUser(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof gameIdBody>,
) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  const read = await readGameState(db, body.game_id);
  if (!read.roster.some((r) => r.user_id === userId)) {
    throw new HttpError(
      403,
      "Not a participant in this game",
      EngineCode.notParticipant,
    );
  }
  await expireGame(gameModule, db, body.game_id);
  return c.json({ ok: true });
}

/** The engine-owned {@link LifecycleAction} payload shapes, for validating a
 * logged lifecycle action during replay. */
const lifecycleActionSchema = z.union([
  z.strictObject({ type: z.literal("timeout") }),
  z.strictObject({
    type: z.enum(["forfeit", "auto_forfeit"]),
    player_index: z.number().int(),
  }),
]);

/** Rebuild the {@link TransitionCause} of one replay frame from its logged
 * action row — null for the initial frame, which no action produced. The
 * live pipeline never reconstructs (it knows the cause first-hand); only
 * replay recovers it from the log, dispatching on the row's `kind` column
 * (stamped at commit) and validating the payload against the matching
 * schema. */
function replayCause(
  rules: GameRules,
  schemaVersion: number,
  action: {
    kind: "game" | "lifecycle";
    data: unknown;
    player_index: number | null;
  } | null,
): TransitionCause {
  if (!action) return null;
  if (action.kind === "lifecycle") {
    const lifecycle = lifecycleActionSchema.safeParse(action.data);
    if (!lifecycle.success) {
      throw new HttpError(
        500,
        "Logged lifecycle action has a malformed payload",
      );
    }
    return { kind: "lifecycle", data: lifecycle.data };
  }
  if (action.player_index === null) {
    throw new HttpError(500, "Logged game action is missing its player_index");
  }
  return {
    kind: "game",
    data: parseStoredPayload(
      rules.schemas.action,
      action.data,
      "action data",
      schemaVersion,
    ),
    playerIndex: action.player_index,
  };
}

export async function handleReplay(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof gameIdBody>,
) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  const replay = await readReplay(db, body.game_id);
  // Gate in TS (the raw read is service-role): finished games only, caller must
  // hold a seat. Affected seats of a timeout come from the pending diff, not
  // the identity-less action row, so action_player_index is null for
  // system-performed lifecycle actions.
  if (replay.status !== "finished") {
    throw new HttpError(400, "Replay is only available for finished games");
  }
  const caller = replay.participants.find((p) => p.user_id === userId);
  if (!caller) {
    throw new HttpError(
      403,
      "Not a participant in this game",
      EngineCode.notParticipant,
    );
  }

  const rules = rulesFor(gameModule, replay.schema_version);
  const config = parseStoredPayload(
    rules.schemas.config,
    replay.config ?? {},
    "config",
    replay.schema_version,
  );
  // Mapping to the declared `ReplayFrame` (game payloads as `unknown`) is what
  // keeps this route's inferred response type finite — see the type's doc.
  const frames = replay.game_states.map((frame): ReplayFrame => {
    const slice = rules.computeObservation({
      state: parseStoredPayload(
        rules.schemas.state,
        frame.state ?? {},
        "state",
        replay.schema_version,
      ),
      pending: frame.pending_players,
      playerIndex: caller.player_index,
      participantCount: replay.participants.length,
      config,
      cause: replayCause(rules, replay.schema_version, frame.actions),
      isReplay: true,
    });
    return {
      version: frame.version,
      data: slice.data,
      pending_players: slice.pending_players,
      created_at: frame.created_at,
      action_type: frame.actions?.type ?? null,
      action_kind: frame.actions?.kind ?? null,
      action_data: frame.actions?.data ?? null,
      action_player_index: frame.actions?.player_index ?? null,
    };
  });
  return c.json(frames);
}

export async function handleLocalBotAction(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof localBotActionBody>,
) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  await applyGameAction(gameModule, db, {
    gameId: body.game_id,
    data: body.data,
    expectedVersion: body.expected_version,
    mode: "bot",
    resolve: (read) => ({
      playerIndex: body.player_index,
      callerId: null,
      botId: assertLocalBotSeat(read, userId, body.player_index),
    }),
  });
  return c.json({ ok: true });
}

export async function handleDeleteAccount(
  gameModule: GameModule,
  c: Context<AppEnv>,
) {
  const { supabaseAdmin: db, userClaims } = c.var.supabaseContext;
  const userId = requireUserId(userClaims?.id);
  await purgeUserGames(gameModule, db, userId);
  return c.json({ ok: true });
}
