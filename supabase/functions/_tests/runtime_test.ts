/** Tests of the pure runtime infra: error-code registry, status mapping,
 * Zod issue summaries, and the optimistic commit-retry loop. */

import { assert, assertEquals, assertMatch, assertRejects } from "@std/assert";
import {
  commitWithRetry,
  EngineCode,
  HttpError,
  issueSummary,
  rpcErrorStatus,
} from "engine/runtime.ts";

Deno.test("EngineCode values are unique EIGxx codes", () => {
  const codes = Object.values(EngineCode);
  assertEquals(new Set(codes).size, codes.length);
  for (const code of codes) assertMatch(code, /^EIG\d{2}$/);
});

Deno.test("HttpError carries status, message, and code", () => {
  const error = new HttpError(409, "stale", EngineCode.staleVersion);
  assertEquals(error.status, 409);
  assertEquals(error.message, "stale");
  assertEquals(error.code, "EIG02");
});

Deno.test("rpcErrorStatus maps coded errors by code", () => {
  assertEquals(rpcErrorStatus("anything", EngineCode.ratingConflict), 409);
  assertEquals(rpcErrorStatus("anything", EngineCode.gameNotFound), 404);
  assertEquals(rpcErrorStatus("anything", EngineCode.notParticipant), 403);
  assertEquals(rpcErrorStatus("anything", EngineCode.notAuthenticated), 401);
});

Deno.test("rpcErrorStatus prefers the code over message matching", () => {
  assertEquals(rpcErrorStatus("game not found", EngineCode.staleVersion), 409);
});

Deno.test("rpcErrorStatus falls back to message matching, then 500", () => {
  assertEquals(rpcErrorStatus("Game is not ready to start"), 409);
  assertEquals(rpcErrorStatus("Game not found"), 404);
  assertEquals(rpcErrorStatus("Only the creator can start"), 403);
  assertEquals(rpcErrorStatus("something else entirely"), 500);
  assertEquals(rpcErrorStatus("something else", "UNKNOWN_CODE"), 500);
});

Deno.test("issueSummary joins issues, prefixing non-empty paths", () => {
  const summary = issueSummary({
    issues: [
      { path: ["config", "size"], message: "too small" },
      { path: [], message: "unrecognized key" },
    ],
  });
  assertEquals(summary, "config.size: too small; unrecognized key");
});

Deno.test("commitWithRetry retries retryable codes and returns", async () => {
  let attempts = 0;
  const result = await commitWithRetry(
    (code) => code === EngineCode.ratingConflict,
    () => {
      attempts++;
      if (attempts < 3) {
        throw new HttpError(409, "conflict", EngineCode.ratingConflict);
      }
      return Promise.resolve("done");
    },
  );
  assertEquals(result, "done");
  assertEquals(attempts, 3);
});

Deno.test("commitWithRetry exhausts attempts and rethrows the last", async () => {
  let attempts = 0;
  await assertRejects(
    () =>
      commitWithRetry(
        () => true,
        () => {
          attempts++;
          throw new HttpError(409, "conflict", EngineCode.staleVersion);
        },
        3,
      ),
    HttpError,
    "conflict",
  );
  assertEquals(attempts, 3);
});

Deno.test("commitWithRetry does not retry non-retryable errors", async () => {
  let attempts = 0;
  await assertRejects(
    () =>
      commitWithRetry(
        (code) => code === EngineCode.ratingConflict,
        () => {
          attempts++;
          throw new HttpError(409, "stale", EngineCode.staleVersion);
        },
      ),
    HttpError,
  );
  assertEquals(attempts, 1);
});

Deno.test("commitWithRetry does not retry non-HttpError throws", async () => {
  let attempts = 0;
  await assertRejects(
    () =>
      commitWithRetry(
        () => true,
        () => {
          attempts++;
          throw new Error("bug");
        },
      ),
    Error,
    "bug",
  );
  assertEquals(attempts, 1);
});

Deno.test("commitWithRetry passes a first-try success through", async () => {
  assert(await commitWithRetry(() => false, () => Promise.resolve(true)));
});
