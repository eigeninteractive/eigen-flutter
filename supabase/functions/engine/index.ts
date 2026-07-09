/**
 * `engine` Edge Function — the single engine harness. Mounts every engine
 * route group over your app's gameModule and serves it (routing, per-group
 * auth, gated reads/commits — all under `_engine/`):
 *
 *   - `/engine/game/*`     client-facing game routes (verified user JWT)
 *   - `/engine/social/*`   friend writes (verified user JWT)
 *   - `/engine/internal/*` DB/cron routes (secret API key)
 *   - `/engine/bot/*`      server-bot action (per-bot HMAC)
 *
 * **Vendored — do not edit.** `dart run eigen_engine:sync_supabase` overwrites
 * this file on every sync. Your only seam is {@link ../_lib/game.ts} — implement
 * your {@link GameModule} there. See docs/game_implementation_guide.md.
 */

import { createEngineApp } from "engine/app.ts";
import { gameModule } from "lib/game.ts";

export default { fetch: createEngineApp(gameModule).fetch };
