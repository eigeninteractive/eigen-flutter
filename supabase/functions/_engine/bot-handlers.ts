/**
 * Request-body schema and handler for the engine's server-bot group
 * (`/engine/bot/*`).
 *
 * The route is registered in `app.ts` with `auth: 'none'`: a server bot
 * carries no JWT, so the handler authenticates the request itself by verifying
 * the bot's HMAC over the exact signed `payload` string before trusting any of
 * its claims. The move itself runs through the shared pipeline in
 * `game-pipeline.ts`.
 */

import type { Context } from "@hono/hono";
import type { GameEngine } from "types/engine.types.ts";
import { z } from "zod";
import { verifyBotSignature } from "./bot_auth.ts";
import { parseClientPayload } from "./game-engine.ts";
import { applyMove } from "./game-pipeline.ts";
import { type AppEnv, HttpError } from "./runtime.ts";

export const botActionBody = z.object({
  payload: z.string(),
  signature: z.string(),
});

/** What a server bot signs: its claimed identity/seat, the version it acted
 * against, and the move. Verified against the bot's HMAC over the exact
 * `payload` string before any of it is trusted. */
const botClaim = z.object({
  bot_id: z.string(),
  game_id: z.string(),
  player_index: z.number().int().min(0),
  version: z.number().int(),
  data: z.unknown(),
});

export async function handleBotAction(
  gameEngine: GameEngine,
  c: Context<AppEnv>,
  body: z.infer<typeof botActionBody>,
) {
  const { supabaseAdmin: db } = c.var.supabaseContext;
  let parsed: unknown;
  try {
    parsed = JSON.parse(body.payload);
  } catch {
    throw new HttpError(400, "payload is not JSON");
  }
  const claim = parseClientPayload(botClaim, parsed, "bot claim");

  if (
    !(await verifyBotSignature(
      claim.bot_id,
      "action",
      body.payload,
      body.signature,
    ))
  ) {
    throw new HttpError(401, "Unauthorized");
  }

  await applyMove(gameEngine, db, {
    gameId: claim.game_id,
    data: claim.data,
    expectedVersion: claim.version,
    mode: "bot",
    resolve: (read) => {
      const seat = read.roster.find(
        (r) =>
          r.bot_id === claim.bot_id && r.player_index === claim.player_index,
      );
      if (!seat) {
        throw new HttpError(
          403,
          `Bot does not hold seat ${claim.player_index}`,
        );
      }
      return {
        playerIndex: claim.player_index,
        callerId: null,
        botId: claim.bot_id,
      };
    },
  });
  return c.json({ ok: true });
}
