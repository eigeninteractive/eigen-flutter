/**
 * Request-body schemas and handlers for the engine's internal group
 * (`/engine/internal/*`) — the pg_cron sweeps.
 *
 * Routes are registered in `app.ts`; the group is authenticated with the
 * project's secret API key (`auth: 'secret'` — pg_net posts it in the `apikey`
 * header), so no user identity exists here. Both sweeps are best-effort batch
 * drivers over the shared pipeline in `game-pipeline.ts`: a per-item failure
 * is logged and skipped, and the self-healing sweep re-selects it next tick.
 */

import type { Context } from "@hono/hono";
import { pooledMap } from "@std/async";
import type { GameModule } from "types/engine.types.ts";
import { z } from "zod";
import { expireGame, purgeUserGames } from "./game-pipeline.ts";
import type { AppEnv } from "./runtime.ts";

export const expireBatchBody = z.object({ game_ids: z.array(z.string()) });

export const purgeUsersBody = z.object({ user_ids: z.array(z.string()) });

/** How many expire pipelines run concurrently per batch. The batch entries are
 * independent games (the sweep query is DISTINCT ON game_id), so this is a
 * throughput cap, not a correctness guard: it bounds concurrent PostgREST
 * connections while keeping a full 200-game batch (~25 waves) well inside the
 * EF wall clock, where the old sequential drain risked brushing against it. */
const expireConcurrency = 8;

/** The pg_cron expire sweep drives the timeout for a batch of games in one
 * hop (the participant nudge in `game-handlers.ts` is the per-game driver). */
export async function handleExpireBatch(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof expireBatchBody>,
) {
  const { supabaseAdmin: db } = c.var.supabaseContext;
  let processed = 0;
  let failed = 0;
  // Failures are absorbed per game — pooledMap aborts the pool on a rejected
  // item, which must never strand the rest of a self-healing sweep.
  const expirations = pooledMap(expireConcurrency, body.game_ids, async (
    gameId,
  ) => {
    try {
      await expireGame(gameModule, db, gameId);
      processed++;
    } catch (e) {
      console.error(`expire failed for ${gameId}:`, e);
      failed++;
    }
  });
  await Array.fromAsync(expirations);
  // The cron caller PERFORMs net.http_post and discards the response, so the
  // outcome is logged rather than returned.
  console.log(`expire batch: ${processed} processed, ${failed} failed`);
  return c.json({ ok: true });
}

/** Forfeit-then-purge a batch of users. The stale-guest sweep sends only
 * guests that still hold active games — purging a guest with no active games
 * is pure SQL and runs in the sweep itself. Each user needs the rules (a
 * forfeit's consequence is game-defined and may leave a multiplayer game
 * active), so this cannot be a per-game signal. Sequential on purpose (unlike
 * the expire batch): two purged users can share an active game, and running
 * them serially avoids churning the forfeit retry path for a sweep that has
 * tiny batches and no latency requirement. */
export async function handlePurgeUsers(
  gameModule: GameModule,
  c: Context<AppEnv>,
  body: z.infer<typeof purgeUsersBody>,
) {
  const { supabaseAdmin: db } = c.var.supabaseContext;
  let purged = 0;
  for (const userId of body.user_ids) {
    try {
      await purgeUserGames(gameModule, db, userId);
      purged++;
    } catch (e) {
      console.error(`Failed to purge user ${userId}:`, e);
    }
  }
  return c.json({ ok: true, purged });
}
