/**
 * The engine's repository — the single seam between the EF and the database.
 * Typed reads and the gated `engine_*` write RPCs all live here; no other
 * engine module issues a query, so migrating storage touches this file alone.
 *
 * Reads query the tables directly with the service-role client (every table is
 * RLS-deny-all, so only this trusted EF can read them) and **map** the typed
 * result into a read view. The view types are *inferred* from the mappers and
 * exported here ({@link ReadGameState}, {@link Seat}) — never hand-declared —
 * so adding a column flows through in one place. The RPC arg types come from
 * the generated schema with the engine-owned wire shapes corrected by the
 * `Database` override in {@link ../_types/engine.types.ts}, so writes need no
 * param interfaces or casts either.
 */

import type { SupabaseClient } from "@supabase/server/peer/supabase-js";
import type {
  AcceptFriendResult,
  Database,
  JsonObject,
  SendFriendResult,
} from "types/engine.types.ts";
import { EngineCode, HttpError, rpcErrorStatus } from "./runtime.ts";

/** The typed service-role client every engine module passes into this seam. */
export type Db = SupabaseClient<Database>;
type RpcArgs<Name extends keyof Database["public"]["Functions"]> =
  Database["public"]["Functions"][Name]["Args"];

// ── Game reads ────────────────────────────────────────────────────────────────

/** Read the ground-truth a move/forfeit/timeout needs: game meta, the latest
 * state (`rng_seed` is the game's base seed, constant across rows), and the
 * participant roster (bot seats carry their wake fields). A game is `active`
 * iff it has a committed state, so an active game always has a `latest`; a
 * stateless lobby is rejected. */
export async function readGameState(db: Db, gameId: string) {
  const { data, error } = await db
    .from("games")
    .select(
      "config, schema_version, status, rated, rating_pool, budget_seconds, participants(player_index, user_id, bot_id, bots(webhook_url, is_local)), game_states(version, state, pending_players, rng_seed)",
    )
    .eq("id", gameId)
    .order("version", { referencedTable: "game_states", ascending: false })
    .limit(1, { referencedTable: "game_states" })
    .maybeSingle();
  if (error) throw new HttpError(500, error.message);
  if (!data) {
    throw new HttpError(404, "Game not found", EngineCode.gameNotFound);
  }
  const latest = data.game_states[0];
  if (!latest) throw new HttpError(409, "Game has no committed state");
  return {
    meta: {
      config: (data.config ?? {}) as JsonObject,
      schema_version: data.schema_version,
      status: data.status,
      rated: data.rated,
      rating_pool: data.rating_pool,
      budget_seconds: data.budget_seconds,
    },
    latest: {
      version: latest.version,
      state: (latest.state ?? {}) as JsonObject,
      pending_players: latest.pending_players,
      rng_seed: latest.rng_seed,
    },
    roster: [...data.participants]
      .sort((a, b) => a.player_index - b.player_index)
      .map((p) => ({
        player_index: p.player_index,
        user_id: p.user_id,
        bot_id: p.bot_id,
        webhook_url: p.bots?.webhook_url ?? null,
        is_local: p.bots?.is_local ?? false,
      })),
  };
}

/** The assembled game-state read view — game meta, the latest frame, and the
 * sorted roster — inferred from {@link readGameState}'s mapper. */
export type ReadGameState = Awaited<ReturnType<typeof readGameState>>;

/** One roster seat (bot seats carry the wake fields). */
export type Seat = ReadGameState["roster"][number];

/** Read what the EF needs to compute the initial state. `created_by` backs the
 * route's creator fast-fail (the hooks + fan-out must not run for a
 * non-creator); status `ready` and the authoritative creator check are
 * enforced by the commit RPC under its lock. */
export async function readForStart(db: Db, gameId: string) {
  const { data, error } = await db
    .from("games")
    .select(
      "config, schema_version, status, rated, rating_pool, budget_seconds, created_by, participants(count)",
    )
    .eq("id", gameId)
    .maybeSingle();
  if (error) throw new HttpError(500, error.message);
  if (!data) {
    throw new HttpError(404, "Game not found", EngineCode.gameNotFound);
  }
  return {
    config: (data.config ?? {}) as JsonObject,
    schema_version: data.schema_version,
    status: data.status,
    rated: data.rated,
    rating_pool: data.rating_pool,
    budget_seconds: data.budget_seconds,
    created_by: data.created_by,
    player_count: data.participants[0]?.count ?? 0,
  };
}

/** Active game ids a user holds a seat in — the EF forfeits these (via the
 * rules) before purging the account. */
export async function readActiveGameIds(
  db: Db,
  userId: string,
): Promise<string[]> {
  const { data, error } = await db
    .from("participants")
    .select("game_id, games!inner(status)")
    .eq("user_id", userId)
    .eq("games.status", "active");
  if (error) throw new HttpError(500, error.message);
  return (data ?? []).map((r) => r.game_id);
}

/** Every historical state with its producing action, for the replay route to
 * project through the observation hook. Raw state returned only to the trusted
 * EF; `handleReplay` applies the finished + participant gate. */
export async function readReplay(db: Db, gameId: string) {
  const { data, error } = await db
    .from("games")
    .select(
      "config, schema_version, status, participants(player_index, user_id), game_states(version, state, pending_players, created_at, actions(type, kind, data, player_index))",
    )
    .eq("id", gameId)
    .order("version", { referencedTable: "game_states" })
    .maybeSingle();
  if (error) throw new HttpError(500, error.message);
  if (!data) {
    throw new HttpError(404, "Game not found", EngineCode.gameNotFound);
  }
  return data;
}

/** Current `(mu, sigma, revision)` for the given identities in a pool — read on a
 * rated finishing transition to feed `computeRatings` and the optimistic
 * `expected_revision`. A missing identity (never rated) is simply absent; the
 * caller defaults it (rating defaults + `revision` 0). */
export async function readRatingsForSeats(
  db: Db,
  pool: string,
  userIds: string[],
  botIds: string[],
) {
  const clauses: string[] = [];
  if (userIds.length) clauses.push(`user_id.in.(${userIds.join(",")})`);
  if (botIds.length) clauses.push(`bot_id.in.(${botIds.join(",")})`);
  if (clauses.length === 0) return [];
  const { data, error } = await db
    .from("player_ratings")
    .select("user_id, bot_id, mu, sigma, revision")
    .eq("pool", pool)
    .or(clauses.join(","));
  if (error) throw new HttpError(500, error.message);
  return data ?? [];
}

/** A bot's seating-relevant fields, read by the EF so the gated seat RPCs no
 * longer carry the bot-class/schema policy (it lives in TS). `config` feeds the
 * `botSeatable` game hook; `isLocal` / `schemaVersion` gate the solo bot-class
 * and compatibility rules. */
export interface BotInfo {
  config: JsonObject;
  isLocal: boolean;
  schemaVersion: number;
}

/** Read the seating-relevant fields for a set of bots. */
export async function readBots(
  db: Db,
  botIds: string[],
): Promise<Map<string, BotInfo>> {
  const { data, error } = await db
    .from("bots")
    .select("id, config, is_local, schema_version")
    .in("id", botIds);
  if (error) throw new HttpError(500, error.message);
  // config is typed as Json (union) in the DB schema; we know it's always an
  // object in practice — cast to JsonObject at this boundary.
  return new Map(
    (data ?? []).map((r) => [
      r.id,
      {
        config: (r.config ?? {}) as JsonObject,
        isLocal: r.is_local,
        schemaVersion: r.schema_version,
      },
    ]),
  );
}

/** Read a game's opaque `config` blob and its `schema_version` — the pair the
 * caller needs to parse the config (pre-start, so {@link readGameState} —
 * which needs a committed state row — can't be used). */
export async function readGameConfig(db: Db, gameId: string) {
  const { data, error } = await db
    .from("games")
    .select("config, schema_version")
    .eq("id", gameId)
    .maybeSingle();
  if (error) throw new HttpError(500, error.message);
  if (!data) {
    throw new HttpError(404, "Game not found", EngineCode.gameNotFound);
  }
  return {
    config: (data.config ?? {}) as JsonObject,
    schema_version: data.schema_version,
  };
}

// ── Notification reads (consumed by notify.ts) ────────────────────────────────

/** All FIDs (Firebase Installation IDs) registered to a user's devices. */
export async function readUserFids(db: Db, userId: string): Promise<string[]> {
  const { data, error } = await db
    .from("device_installations")
    .select("fid")
    .eq("user_id", userId);
  if (error) throw new HttpError(500, error.message);
  return (data ?? []).map((r) => r.fid);
}

/** Delete device registrations FCM reported as permanently unregistered. */
export async function pruneFids(
  db: Db,
  userId: string,
  fids: string[],
): Promise<void> {
  const { error } = await db
    .from("device_installations")
    .delete()
    .eq("user_id", userId)
    .in("fid", fids);
  if (error) throw new HttpError(500, error.message);
}

/** What a friends-game invite push needs: the creator's display name, the
 * lobby short code, and every accepted friend of the creator. Null when the
 * game isn't a friends-access game (or has no creator) — the caller no-ops. */
export async function readGameInviteContext(db: Db, gameId: string) {
  const { data: game, error } = await db
    .from("games")
    .select("created_by, access, short_code")
    .eq("id", gameId)
    .maybeSingle();
  if (error) throw new HttpError(500, error.message);
  if (!game || game.access !== "friends" || !game.created_by) return null;

  const { data: profile } = await db
    .from("user_profiles")
    .select("display_name")
    .eq("id", game.created_by)
    .maybeSingle();

  const { data: rels, error: relsError } = await db
    .from("relationships")
    .select("user_id_1, user_id_2")
    .eq("status", "accepted")
    .or(`user_id_1.eq.${game.created_by},user_id_2.eq.${game.created_by}`);
  if (relsError) throw new HttpError(500, relsError.message);

  return {
    shortCode: game.short_code,
    creatorName: profile?.display_name ?? null,
    friendIds: (rels ?? []).map((r) =>
      r.user_id_1 === game.created_by ? r.user_id_2 : r.user_id_1
    ),
  };
}

/** Resolve `player_index → display_name` for every identified seat in the
 * roster. Seats without a display name are omitted. */
export async function readDisplayNames(
  db: Db,
  roster: Seat[],
): Promise<Map<number, string>> {
  const names = new Map<number, string>();
  const seatByUser = new Map<string, number>();
  const seatByBot = new Map<string, number>();
  for (const seat of roster) {
    if (seat.user_id) seatByUser.set(seat.user_id, seat.player_index);
    if (seat.bot_id) seatByBot.set(seat.bot_id, seat.player_index);
  }

  if (seatByUser.size > 0) {
    const { data } = await db
      .from("user_profiles")
      .select("id, display_name")
      .in("id", [...seatByUser.keys()]);
    for (const row of data ?? []) {
      const idx = seatByUser.get(row.id);
      if (idx !== undefined) names.set(idx, row.display_name);
    }
  }

  if (seatByBot.size > 0) {
    const { data } = await db
      .from("bots")
      .select("id, display_name")
      .in("id", [...seatByBot.keys()]);
    for (const row of data ?? []) {
      const idx = seatByBot.get(row.id);
      if (idx !== undefined) names.set(idx, row.display_name);
    }
  }

  return names;
}

/** One seat's freshly-committed (latest) observation row, for the server-bot
 * wake — observations are append-only, one row per seat per version. Null
 * when absent (e.g. the fan-out raced) — the caller skips the wake. */
export async function readSeatObservation(
  db: Db,
  gameId: string,
  playerIndex: number,
) {
  const { data, error } = await db
    .from("observations")
    .select("data, version, pending_players, turn_deadline")
    .eq("game_id", gameId)
    .eq("player_index", playerIndex)
    .order("version", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw new HttpError(500, error.message);
  return data;
}

// ── Gated write RPCs ──────────────────────────────────────────────────────────

/** Pure-SQL account teardown: cancel created lobbies, leave joined lobbies, then
 * delete the auth user (active-game forfeits run via the rules first). */
export async function purgeUser(db: Db, userId: string) {
  const { error } = await db.rpc("engine_purge_user", { p_user_id: userId });
  if (error) throw new HttpError(500, error.message);
}

export async function commitAction(
  db: Db,
  params: RpcArgs<"engine_commit_action">,
) {
  const { error } = await db.rpc("engine_commit_action", params);
  // Thread the SQLSTATE through so optimistic-conflict retries can classify it.
  if (error) {
    throw new HttpError(
      rpcErrorStatus(error.message, error.code),
      error.message,
      error.code,
    );
  }
}

export async function commitStart(
  db: Db,
  params: RpcArgs<"engine_commit_start">,
) {
  const { error } = await db.rpc("engine_commit_start", params);
  if (error) throw new HttpError(rpcErrorStatus(error.message), error.message);
}

export async function createGame(
  db: Db,
  params: RpcArgs<"engine_create_game">,
) {
  const { data, error } = await db.rpc("engine_create_game", params);
  if (error) throw new HttpError(rpcErrorStatus(error.message), error.message);
  return data;
}

export async function createSoloGame(
  db: Db,
  params: RpcArgs<"engine_create_solo_game">,
) {
  const { data, error } = await db.rpc("engine_create_solo_game", params);
  if (error) throw new HttpError(rpcErrorStatus(error.message), error.message);
  return data;
}

export async function addBotToGame(
  db: Db,
  callerId: string,
  gameId: string,
  botId: string,
) {
  const { error } = await db.rpc("engine_add_bot_to_game", {
    p_caller_id: callerId,
    p_game_id: gameId,
    p_bot_id: botId,
  });
  if (error) throw new HttpError(rpcErrorStatus(error.message), error.message);
}

export async function sendFriendRequest(
  db: Db,
  callerId: string,
  targetId: string,
) {
  const { data, error } = await db.rpc("engine_send_friend_request", {
    p_caller_id: callerId,
    p_target_user_id: targetId,
  });
  if (error) throw new HttpError(rpcErrorStatus(error.message), error.message);
  return (data as SendFriendResult[])[0];
}

export async function acceptFriendRequest(
  db: Db,
  callerId: string,
  targetId: string,
) {
  const { data, error } = await db.rpc("engine_accept_friend_request", {
    p_caller_id: callerId,
    p_target_user_id: targetId,
  });
  if (error) throw new HttpError(rpcErrorStatus(error.message), error.message);
  return (data as AcceptFriendResult[])[0];
}

export async function removeFriend(db: Db, callerId: string, targetId: string) {
  const { error } = await db.rpc("engine_remove_friend", {
    p_caller_id: callerId,
    p_target_user_id: targetId,
  });
  if (error) throw new HttpError(rpcErrorStatus(error.message), error.message);
}
