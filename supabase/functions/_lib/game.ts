/**
 * App gameModule — the single seam you own in the `game` edge function.
 *
 * Export your {@link GameModule} here as `gameModule`; the engine-owned
 * harness ({@link ../engine/index.ts}) imports this instance and serves it —
 * you never touch the routing, auth, gated reads, or commits.
 *
 * The engine is just the version registry: one {@link GameRules} unit per
 * `schema_version` this build ships, keyed by that version. The harness owns
 * all dispatch — every request resolves the game row's version entry and
 * invokes that unit's hooks, so game code never branches on version. The keys
 * are sparse on purpose: creation rejects a version not present here, and a
 * drained old version is retired by deleting its entry (and its file).
 *
 * Shipping a breaking rules/shape change = adding `./game/v2.ts` (reusing
 * unchanged pieces from `./game/v1.ts` by import) and registering it below;
 * the Dart side mirrors this with a `GameRules` twin per version in
 * `lib/game/`. Keep the twins in sync (this side is authoritative).
 *
 * `dart run eigen_engine:sync_supabase` scaffolds `_lib/` once from the
 * engine example and then **never overwrites it** — it is yours to edit
 * (unlike `index.ts`/`deno.json`, which the engine owns and re-vendors every
 * sync).
 */

import type { GameModule } from "types/engine.types.ts";
import { rulesV1 } from "./game/v1.ts";

/** The app's gameModule instance, served by the engine harness in `index.ts`.
 * The bare `GameModule` annotation is the deliberate seam: it type-checks the
 * version registry against the contract the harness consumes. */
export const gameModule: GameModule = {
  versions: { 1: rulesV1 },
};
