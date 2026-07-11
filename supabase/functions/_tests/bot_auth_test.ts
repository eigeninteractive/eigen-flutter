/** Tests of the server-bot HMAC scheme in `_engine/bot_auth.ts`: sign/verify
 * round-trips, direction binding, per-bot key derivation, and malformed
 * signature handling. Needs `--allow-env` (the master secret is an env var,
 * set here). */

import { assert, assertMatch } from "@std/assert";
import { signForBot, verifyBotSignature } from "engine/bot_auth.ts";

Deno.env.set("BOT_SIGNING_SECRET", "test-master-secret");

const payload = JSON.stringify({ game_id: "g1", version: 3 });

Deno.test("a wake signature verifies for the same bot and domain", async () => {
  const signature = await signForBot("bot-1", "wake", payload);
  assertMatch(signature, /^v1,/);
  assert(await verifyBotSignature("bot-1", "wake", payload, signature));
});

Deno.test("an action signature verifies in its own domain", async () => {
  const signature = await signForBot("bot-1", "action", payload);
  assert(await verifyBotSignature("bot-1", "action", payload, signature));
});

Deno.test("a signature never verifies in the other direction", async () => {
  const wake = await signForBot("bot-1", "wake", payload);
  assert(!(await verifyBotSignature("bot-1", "action", payload, wake)));
});

Deno.test("a signature is bound to its bot's derived key", async () => {
  const signature = await signForBot("bot-1", "wake", payload);
  assert(!(await verifyBotSignature("bot-2", "wake", payload, signature)));
});

Deno.test("a tampered payload fails verification", async () => {
  const signature = await signForBot("bot-1", "wake", payload);
  assert(
    !(await verifyBotSignature("bot-1", "wake", payload + "x", signature)),
  );
});

Deno.test("an unknown scheme prefix is rejected", async () => {
  const signature = await signForBot("bot-1", "wake", payload);
  const v2 = "v2," + signature.slice(3);
  assert(!(await verifyBotSignature("bot-1", "wake", payload, v2)));
});

Deno.test("a signature without a scheme prefix is rejected", async () => {
  assert(!(await verifyBotSignature("bot-1", "wake", payload, "no-comma")));
});

Deno.test("malformed base64 is rejected, not thrown", async () => {
  assert(!(await verifyBotSignature("bot-1", "wake", payload, "v1,???")));
});
