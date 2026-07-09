/**
 * The shared game pipeline — the read → resolve → hook → fan-out → commit
 * machinery every state-transitioning route runs, plus the roster guards that
 * validate who is acting. Route-group handler modules (`game-handlers.ts`,
 * `internal-handlers.ts`, `bot-handlers.ts`) compose these; nothing here
 * touches the Hono context, so the pipeline stays a plain function layer over
 * the repo.
 *
 * Retry semantics live here too: a user/bot move only retries a stale rating
 * baseline, a forfeit additionally retries a board advance, and a timeout
 * abstains in SQL when a real action won the race.
 */

import { rating } from "openskill";
import type {
  CommitTransitionWire,
  Envelope,
  EventData,
  GameModule,
  PlayerInput,
  RatingWrite,
} from "types/engine.types.ts";
import {
  assertHookState,
  IllegalMoveError,
  parseClientPayload,
  parseStoredPayload,
  rulesFor,
} from "./game-engine.ts";
import { notifyTransition } from "./notify.ts";
import { deriveRng, fanOutObservations, toTransition } from "./observation.ts";
import { computeRatings } from "./ratings.ts";
import type { Db, ReadGameState } from "./repo.ts";
import {
  commitAction,
  purgeUser,
  readActiveGameIds,
  readGameState,
  readRatingsForSeats,
} from "./repo.ts";
import { commitWithRetry, EngineCode, HttpError } from "./runtime.ts";

declare global {
  /** Injected by the Supabase Edge runtime. Its shipped `edge-runtime.d.ts`
   * doesn't register ambient types under `deno check`, so the one API the
   * engine uses is declared here. `waitUntil` keeps the worker alive until the
   * promise settles, so a post-response notify isn't dropped; on a platform
   * without `EdgeRuntime` the call throws loudly (deliberately unguarded). */
  namespace EdgeRuntime {
    function waitUntil<T>(promise: Promise<T>): Promise<T>;
  }
}

/** A user/bot move only retries when its rating baseline moved — never on a
 * board advance (a moved board must reject the move, not silently re-apply it). */
const isRatingConflict = (code: string | undefined): boolean =>
  code === EngineCode.ratingConflict;

/** A forfeit additionally retries a board advance: it recomputes the forfeit
 * against the new state (the existing optimistic-forfeit behaviour). */
const isForfeitRetryable = (code: string | undefined): boolean =>
  code === EngineCode.ratingConflict || code === EngineCode.staleVersion;

// ── Roster guards ─────────────────────────────────────────────────────────────

/** The caller's seat in the roster, or 403 for a non-participant. */
export function seatOf(read: ReadGameState, userId: string): number {
  const seat = read.roster.find((r) => r.user_id === userId);
  if (!seat) {
    throw new HttpError(
      403,
      "Not a participant in this game",
      EngineCode.notParticipant,
    );
  }
  return seat.player_index;
}

/** The sole-human + local-bot gate for client-driven bot moves, run in TS
 * against the roster the route already read (no extra round-trip). Mirrors
 * `private.resolve_local_bot_seat`, which still backs the direct-client
 * `app_local_bot_observation` RPC where the gate can only live in SQL. Returns
 * the seat's `bot_id`. */
export function assertLocalBotSeat(
  read: ReadGameState,
  userId: string,
  playerIndex: number,
): string {
  if (!read.roster.some((r) => r.user_id === userId)) {
    throw new HttpError(
      403,
      "Not a participant in this game",
      EngineCode.notParticipant,
    );
  }
  const seat = read.roster.find((r) => r.player_index === playerIndex);
  if (!seat?.bot_id) {
    throw new HttpError(400, `Seat ${playerIndex} is not a bot in this game`);
  }
  // Local bots only: a server bot acts solely through the HMAC-authenticated
  // bot route, so a client must not drive (or read) one — that would let a
  // participant front-run the opponent bot in a multi-human or rated game.
  if (!seat.is_local) {
    throw new HttpError(
      403,
      `Seat ${playerIndex} is a server bot and cannot be driven by a client`,
    );
  }
  // Sole-human gate: the caller is a participating human, so exactly one human
  // means the caller is alone — nobody to cheat against.
  if (read.roster.filter((r) => r.user_id !== null).length !== 1) {
    throw new HttpError(403, "Local bot play is only available in a solo game");
  }
  return seat.bot_id;
}

// ── Pipeline ──────────────────────────────────────────────────────────────────

/** Rating writes for a finishing transition, or null when the game is ongoing,
 * unrated, or a single-player result. Reads each identity's current `(mu, sigma,
 * revision)`, computes the OpenSkill posteriors, and attaches the `revision` as
 * `expected_revision` so the commit can compare-and-swap (0 ⇒ never rated). */
async function resolveRatingUpdates(
  db: Db,
  read: ReadGameState,
  envelope: Envelope,
): Promise<RatingWrite[] | null> {
  const outcome = envelope.outcome;
  if (!outcome || outcome.length < 2 || !read.meta.rated) return null;

  const pool = read.meta.rating_pool;
  if (!pool) throw new HttpError(500, "Rated game has no rating_pool");

  // Identities + seat come from the roster the route already read; only the
  // current (mu, sigma, revision) needs fetching.
  const seatByIndex = new Map(read.roster.map((s) => [s.player_index, s]));
  const keyOf = (id: { user_id: string | null; bot_id: string | null }) =>
    id.user_id ? `u:${id.user_id}` : `b:${id.bot_id}`;
  const seats = outcome.map((o) => {
    const seat = seatByIndex.get(o.player_index);
    if (!seat) throw new HttpError(500, `No roster seat ${o.player_index}`);
    return { o, seat, key: keyOf(seat) };
  });

  const ratings = await readRatingsForSeats(
    db,
    pool,
    seats.flatMap(({ seat }) => (seat.user_id ? [seat.user_id] : [])),
    seats.flatMap(({ seat }) => (seat.bot_id ? [seat.bot_id] : [])),
  );
  const byKey = new Map(ratings.map((r) => [keyOf(r), r]));
  const fallback = rating(); // openskill default mu / sigma for never-rated

  const players: PlayerInput[] = seats.map(({ o, seat, key }) => {
    const r = byKey.get(key) ?? fallback;
    return {
      player_index: o.player_index,
      user_id: seat.user_id,
      bot_id: seat.bot_id,
      mu: r.mu,
      sigma: r.sigma,
      placement: o.placement,
      team_index: o.team_index,
    };
  });

  // Attach each identity's read revision as the CAS token; a never-rated identity
  // (absent from `byKey`) carries revision 0 — the sentinel for "no row yet".
  return computeRatings(players).map((result) => {
    const key = "user_id" in result.identity
      ? `u:${result.identity.user_id}`
      : `b:${result.identity.bot_id}`;
    return { ...result, expected_revision: byKey.get(key)?.revision ?? 0 };
  });
}

/** Apply a human or bot move: read → resolve seat → guard → gameModule → fan-out
 * → commit, retrying transparently when a rated finish hits a stale rating
 * baseline (the only retryable conflict for a move — a board advance must reject).
 *
 * `resolve` runs against the freshly-read state each attempt: it validates the
 * caller's seat/identity and returns who is acting. Re-reading on retry is safe
 * because a rating conflict rolls the finish back, leaving the board at the same
 * version; a *real* board advance instead trips the version guard below and
 * propagates (non-retryable). */
export function applyMove(
  gameModule: GameModule,
  db: Db,
  opts: {
    gameId: string;
    data: unknown;
    expectedVersion: number;
    mode: "user" | "bot";
    resolve: (read: ReadGameState) => {
      playerIndex: number;
      callerId: string | null;
      botId: string | null;
    };
  },
): Promise<void> {
  return commitWithRetry(isRatingConflict, async () => {
    const read = await readGameState(db, opts.gameId);
    const { playerIndex, callerId, botId } = opts.resolve(read);

    // Non-authoritative fast-fail: the active-status + version check is enforced
    // authoritatively under the row lock in `engine_commit_action`. Re-checking
    // here lets us skip `applyAction` + the observation fan-out + a doomed RPC
    // when the board has obviously advanced. It cannot diverge harmfully — if it
    // passes but the state moved before the locked commit, the SQL still rejects.
    if (read.meta.status !== "active") {
      throw new HttpError(409, "Game is not active", EngineCode.gameNotActive);
    }
    if (read.latest.version !== opts.expectedVersion) {
      throw new HttpError(
        409,
        "Stale state: the board has advanced",
        EngineCode.staleVersion,
      );
    }

    const version = read.meta.schema_version;
    const rules = rulesFor(gameModule, version);
    // The sanitized action data also becomes the `actions` log entry below —
    // never the raw client payload.
    const data = parseClientPayload(
      rules.schemas.action,
      opts.data,
      "action data",
    );
    let envelope: Envelope;
    try {
      envelope = rules.applyAction({
        state: parseStoredPayload(
          rules.schemas.state,
          read.latest.state,
          "state",
          version,
        ),
        pending: read.latest.pending_players,
        data,
        playerIndex,
        rng: deriveRng(read.latest.rng_seed, read.latest.version + 1),
        config: parseStoredPayload(
          rules.schemas.config,
          read.meta.config,
          "config",
          version,
        ),
      });
    } catch (e) {
      // The hook's expected failure — a rule-breaking move — is the caller's
      // fault; anything else is a game bug and propagates as a 500.
      if (e instanceof IllegalMoveError) {
        throw new HttpError(400, e.message, EngineCode.illegalMove);
      }
      throw e;
    }
    assertHookState(rules.schemas, envelope, version);

    const observations = fanOutObservations(rules, {
      state: envelope.state,
      pending: envelope.pending_players,
      participantCount: read.roster.length,
      config: read.meta.config,
      cause: { kind: "action", data, playerIndex },
      isReplay: false,
    });
    const ratings = await resolveRatingUpdates(db, read, envelope);

    await commitAction(db, {
      p_mode: opts.mode,
      p_game_id: opts.gameId,
      p_caller_id: callerId,
      p_acting_bot_id: botId,
      p_expected_version: opts.expectedVersion,
      p_transitions: [
        toTransition(envelope, data, playerIndex, observations, ratings),
      ],
    });
    EdgeRuntime.waitUntil(
      notifyTransition(db, {
        gameId: opts.gameId,
        prevPending: read.latest.pending_players,
        finalPending: envelope.pending_players,
        roster: read.roster,
      }),
    );
  });
}

/** Run one system action against the current state and build its commit
 * transition: invoke `handleEvent`, fan out observations, resolve ratings.
 *
 * A `timeout` resolves the **whole pending set** holistically (the hook decides
 * who is out / a draw) into one identity-less transition. A `forfeit` targets one
 * seat (`targetSeat`, passed to the hook via `data.player_index`); a voluntary
 * resign sets `actorSeat` (the performer's seat → recorded on the action), while
 * an engine-driven forfeit leaves it null and becomes `auto_forfeit` — both in
 * the log and in the `type` the hook receives. */
async function applyEvent(
  gameModule: GameModule,
  db: Db,
  read: ReadGameState,
  step:
    | { type: "timeout" }
    | { type: "forfeit"; targetSeat: number; actorSeat: number | null },
): Promise<{ transition: CommitTransitionWire; envelope: Envelope }> {
  // action_data is the log/replay payload. timeout: just the type — affected
  // seats are derived from the pending diff, not stored here. forfeit: the
  // event_type label + the target seat (the hook reads player_index).
  const data: EventData = step.type === "timeout" ? { type: "timeout" } : {
    type: step.actorSeat === null ? "auto_forfeit" : "forfeit",
    player_index: step.targetSeat,
  };
  const version = read.meta.schema_version;
  const rules = rulesFor(gameModule, version);
  const envelope = rules.handleEvent({
    state: parseStoredPayload(
      rules.schemas.state,
      read.latest.state,
      "state",
      version,
    ),
    pending: read.latest.pending_players,
    type: data.type,
    data,
    rng: deriveRng(read.latest.rng_seed, read.latest.version + 1),
    config: parseStoredPayload(
      rules.schemas.config,
      read.meta.config,
      "config",
      version,
    ),
  });
  assertHookState(rules.schemas, envelope, version);
  const observations = fanOutObservations(rules, {
    state: envelope.state,
    pending: envelope.pending_players,
    participantCount: read.roster.length,
    config: read.meta.config,
    cause: { kind: "event", data },
    isReplay: false,
  });
  const ratings = await resolveRatingUpdates(db, read, envelope);
  // Performer seat: only a voluntary resign has one; timeout and engine-driven
  // forfeit are identity-less (null).
  const performerSeat = step.type === "forfeit" ? step.actorSeat : null;
  const transition = toTransition(
    envelope,
    data,
    performerSeat,
    observations,
    ratings,
  );
  return { transition, envelope };
}

/** Forfeit one game, retrying on a stale race.
 *
 * `mode` distinguishes a voluntary **resign** (a user action carrying the
 * resigning user's id + seat) from an engine-driven **forfeit** (account
 * deletion — an identity-less system action). */
export async function forfeitGame(
  gameModule: GameModule,
  db: Db,
  gameId: string,
  userId: string,
  mode: "resign" | "forfeit",
): Promise<void> {
  await commitWithRetry(isForfeitRetryable, async () => {
    const read = await readGameState(db, gameId);
    if (read.meta.status !== "active") return; // already resolved — nothing to do
    const seat = seatOf(read, userId);
    const { transition } = await applyEvent(gameModule, db, read, {
      type: "forfeit",
      targetSeat: seat,
      actorSeat: mode === "resign" ? seat : null,
    });
    await commitAction(db, {
      p_mode: mode,
      p_game_id: gameId,
      p_caller_id: mode === "resign" ? userId : null,
      p_acting_bot_id: null,
      p_expected_version: read.latest.version,
      p_transitions: [transition],
    });
  });
}

/** Forfeit every active game for a user, then run the pure-SQL purge. */
export async function purgeUserGames(
  gameModule: GameModule,
  db: Db,
  userId: string,
): Promise<void> {
  const gameIds = await readActiveGameIds(db, userId);
  for (const gameId of gameIds) {
    await forfeitGame(gameModule, db, gameId, userId, "forfeit");
  }
  await purgeUser(db, userId);
}

/** Resolve a turn timeout and commit. The hook resolves the whole pending set
 * holistically into one identity-less system transition; the SQL commit
 * re-checks expiry under the lock and abstains if a real action won the race.
 * Shared by the user nudge (`game`) and the cron sweep (`internal`). */
export function expireGame(
  gameModule: GameModule,
  db: Db,
  gameId: string,
): Promise<void> {
  return commitWithRetry(isRatingConflict, async () => {
    const read = await readGameState(db, gameId);
    if (read.meta.status !== "active") return;

    const { transition } = await applyEvent(gameModule, db, read, {
      type: "timeout",
    });

    await commitAction(db, {
      p_mode: "timeout",
      p_game_id: gameId,
      p_caller_id: null,
      p_acting_bot_id: null,
      p_expected_version: read.latest.version,
      p_transitions: [transition],
    });
    EdgeRuntime.waitUntil(
      notifyTransition(db, {
        gameId,
        prevPending: read.latest.pending_players,
        finalPending: transition.new_pending,
        roster: read.roster,
      }),
    );
  });
}
