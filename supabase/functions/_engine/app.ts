/**
 * The engine app — one {@link Hono} application serving the single `engine`
 * edge function. The entire API surface is declared here as a single chain
 * (Hono's simple-app style): each route group's `withSupabase` auth mode,
 * then every route. This file reads as the function's contract; the request
 * schemas and handlers live in one `*-handlers.ts` module per route group,
 * and the shared game pipeline in `game-pipeline.ts`.
 *
 * Route groups by auth mode:
 *   - `/engine/game/*`     → client-facing game routes (`auth: 'user'`)
 *   - `/engine/social/*`   → friend writes (`auth: 'user'`)
 *   - `/engine/internal/*` → DB/cron routes (`auth: 'secret'` — pg_net posts
 *     the project's secret API key in the `apikey` header)
 *   - `/engine/bot/*`      → server-bot action (`auth: 'none'`; the handler
 *     verifies the per-bot HMAC itself)
 *
 * `withSupabase` verifies the group's credential and injects a service-role
 * `supabaseAdmin` client as a typed `SupabaseClient<Database>` (via `AppEnv`).
 * User JWTs are verified in-lib via JWKS, so the function ships with
 * `verify_jwt = false` in config.toml (required — the internal and bot
 * callers carry no JWT) and the middleware is the sole verifier.
 *
 * Supabase forwards the full request path (`/engine/...`) to the function, so
 * the app declares `basePath("/engine")` once.
 */

// Platform marker: this code targets the Supabase Edge runtime, which injects
// the `EdgeRuntime` / `Deno` globals (and types `EdgeRuntime.waitUntil`).
// Side-effect import only.
import "@supabase/functions-js/edge-runtime.d.ts";
import { Hono, type MiddlewareHandler } from "@hono/hono";
import { HTTPException } from "@hono/hono/http-exception";
import { withSupabase as withSupabaseUntyped } from "@supabase/server/adapters/hono";
import type { GameModule } from "types/engine.types.ts";
import { botActionBody, handleBotAction } from "./bot-handlers.ts";
import {
  actionBody,
  addBotBody,
  createBody,
  createSoloBody,
  gameIdBody,
  handleAction,
  handleAddBot,
  handleCreate,
  handleCreateSolo,
  handleDeleteAccount,
  handleExpireUser,
  handleForfeit,
  handleLocalBotAction,
  handleReplay,
  handleStart,
  localBotActionBody,
} from "./game-handlers.ts";
import {
  expireBatchBody,
  handleExpireBatch,
  handlePurgeUsers,
  purgeUsersBody,
} from "./internal-handlers.ts";
import { type AppEnv, HttpError, jsonBody } from "./runtime.ts";
import {
  handleFriendAccept,
  handleFriendRemove,
  handleFriendRequest,
  targetBody,
} from "./social-handlers.ts";

/** {@link withSupabaseUntyped}, asserted onto {@link AppEnv}.
 *
 * `@supabase/server`'s docs (typescript-generics.md) type the *core*
 * `withSupabase<Database>()`; the **Hono adapter's** `withSupabase` has no
 * generic (verified against the shipped d.ts of 1.2.0 and 1.3.0) — it
 * returns `MiddlewareHandler<{ supabaseContext: SupabaseContext }>` with the
 * `Database = unknown` default. Passing it bare, per the docs' Hono example,
 * degrades the whole chain's context (`Database` keys collapse to `never` in
 * every handler), so this wrapper asserts the middleware onto {@link AppEnv}
 * — the same env-typing the docs prescribe, applied at the one seam the
 * adapter's signature can't express. Delete it if the adapter ever gains a
 * `<Database>` parameter. */
const withSupabase = (
  ...args: Parameters<typeof withSupabaseUntyped>
): MiddlewareHandler<AppEnv> =>
  withSupabaseUntyped(...args) as MiddlewareHandler<AppEnv>;

/** Build the engine app over the app's gameModule. Called once at function
 * load by `engine/index.ts`. The return type is deliberately inferred: the
 * chain accumulates every route's path, input, and response types into it
 * (exported below as {@link EngineApp}).
 *
 * Every error path — engine `HttpError`s, request validation, and
 * `withSupabase` auth failures — is an {@link HTTPException}, rendered in the
 * `{ error }` shape the clients parse. */
export function createEngineApp(gameModule: GameModule) {
  return (
    new Hono<AppEnv>()
      .basePath("/engine")
      // Auth, declared per route group ahead of the routes it guards.
      .use("/game/*", withSupabase({ auth: "user" }))
      .use("/social/*", withSupabase({ auth: "user" }))
      .use("/internal/*", withSupabase({ auth: "secret" }))
      .use("/bot/*", withSupabase({ auth: "none" }))
      // Game — client-facing.
      .post(
        "/game/create",
        jsonBody(createBody),
        (c) => handleCreate(gameModule, c, c.req.valid("json")),
      )
      .post(
        "/game/create-solo",
        jsonBody(createSoloBody),
        (c) => handleCreateSolo(gameModule, c, c.req.valid("json")),
      )
      .post(
        "/game/add-bot",
        jsonBody(addBotBody),
        (c) => handleAddBot(gameModule, c, c.req.valid("json")),
      )
      .post(
        "/game/action",
        jsonBody(actionBody),
        (c) => handleAction(gameModule, c, c.req.valid("json")),
      )
      .post(
        "/game/start",
        jsonBody(gameIdBody),
        (c) => handleStart(gameModule, c, c.req.valid("json")),
      )
      .post(
        "/game/forfeit",
        jsonBody(gameIdBody),
        (c) => handleForfeit(gameModule, c, c.req.valid("json")),
      )
      .post(
        "/game/replay",
        jsonBody(gameIdBody),
        (c) => handleReplay(gameModule, c, c.req.valid("json")),
      )
      .post(
        "/game/local-bot-action",
        jsonBody(localBotActionBody),
        (c) => handleLocalBotAction(gameModule, c, c.req.valid("json")),
      )
      .post("/game/delete-account", (c) => handleDeleteAccount(gameModule, c))
      .post(
        "/game/expire",
        jsonBody(gameIdBody),
        (c) => handleExpireUser(gameModule, c, c.req.valid("json")),
      )
      // Social — game-agnostic friend writes.
      .post(
        "/social/friend-request",
        jsonBody(targetBody),
        (c) => handleFriendRequest(c, c.req.valid("json").target_user_id),
      )
      .post(
        "/social/accept",
        jsonBody(targetBody),
        (c) => handleFriendAccept(c, c.req.valid("json").target_user_id),
      )
      .post(
        "/social/remove",
        jsonBody(targetBody),
        (c) => handleFriendRemove(c, c.req.valid("json").target_user_id),
      )
      // Internal — pg_cron sweeps.
      .post(
        "/internal/expire",
        jsonBody(expireBatchBody),
        (c) => handleExpireBatch(gameModule, c, c.req.valid("json")),
      )
      .post(
        "/internal/purge-users",
        jsonBody(purgeUsersBody),
        (c) => handlePurgeUsers(gameModule, c, c.req.valid("json")),
      )
      // Bot — per-bot HMAC verified in the handler.
      .post(
        "/bot/action",
        jsonBody(botActionBody),
        (c) => handleBotAction(gameModule, c, c.req.valid("json")),
      )
      .onError((e, c) => {
        if (e instanceof HTTPException) {
          // 4xx is the caller's fault and stays quiet; a 5xx HTTPException is a
          // server fault (an engine HttpError(500) or the adapter's env/client
          // failure, whose original error rides in `cause`) — log it.
          if (e.status >= 500) {
            console.error("engine route failed:", e.cause ?? e);
          }
          // Engine errors ship their stable EngineCode so clients dispatch on
          // `code`, never on the message copy.
          const code = e instanceof HttpError ? e.code : undefined;
          return code
            ? c.json({ error: e.message, code }, e.status)
            : c.json({ error: e.message }, e.status);
        }
        console.error("engine route failed:", e);
        return c.json({ error: "Internal error" }, 500);
      })
  );
}

/** The engine's complete API surface as a type — every route's path, request
 * body, and response shape (Hono RPC). A TypeScript caller can derive a fully
 * typed client with hono/client: `hc<EngineApp>(functionsBaseUrl)`. Type-only:
 * importing it pulls in no runtime code. */
export type EngineApp = ReturnType<typeof createEngineApp>;
