# Eigen Engine — Architecture of Record (Cloudflare-native)

> **Decision (2026-07-14, design locked 2026-07-15).** The engine runs **Cloudflare-only**:
> Workers at the edge, one **Durable Object per game** owning that game's state — live
> *and finished*: the DO's SQLite **is** the game's history (§4.6) — **D1** for global
> data, **Firebase Auth** for identity. **R2** is opt-in (avatar uploads — v1 code,
> simulated free in local dev) or later (history cold tier) — §5.4. No Postgres. No
> Supabase.
>
> **Two sets of keys: a Cloudflare account and a Firebase project.** Nothing else.
>
> **The constraints that drove it:** fast time-to-first-game, **scale to zero** when idle,
> **~$10/month** at real traffic. We start on the **Workers free plan** — everything the
> design needs (SQLite-backed DOs, alarms, hibernation, D1, cron) is on it, **with no
> payment method on file** (which R2 would require even for free use — §5.4) — and
> upgrade to paid ($5/mo) at the traffic trigger defined in §10. The upgrade is one click,
> zero code change.
>
> **Cutover is big-bang.** The Supabase stack (documented in `engine_architecture.md`, now
> the *legacy* reference) is frozen bugfix-only; `supabase/` is deleted from this repo at
> parity. There are no production users, so there is no data migration.

This document is the **final architecture**: every design decision below is settled, not
proposed. `engine_architecture.md` remains the reference for the frozen Supabase system —
useful because most *semantics* (hooks, timing, ratings, bots, guests, deletion) carry over
verbatim; only the *host machinery* changes.

**Contents.** §1 stack · §2 repos & packages · §3 the core (kernel, DO, commands, same-view
rule) · §4 game lifecycle end to end · §5 data · §6 identity · §7 push & bots · §8 failure
policy · §9 client · §10 cost · §11 CI & testkit · §12 non-negotiables · §13 what we gave up
· §14 build plan · §15 repo setup instructions · Appendix: rejected alternatives.

---

## 1. The stack

| Layer | Choice | Notes |
| --- | --- | --- |
| Client | **Flutter** — opinionated, the only client | `firebase_auth`, FCM, Analytics, Crashlytics |
| Identity | **Firebase Auth** | Google · Apple · **Anonymous**, `linkWithCredential` guest→permanent upgrade |
| Edge | **Cloudflare Workers** (hono) | Stateless: verify token (**jose**), serve D1 reads, mint commands, route to DOs |
| Game session + history | **One Durable Object per game** | SQLite-backed; owns state, roster, sockets, the alarm — and is retained after finish as the game's history (§4.6) |
| Global store | **D1** | Identity, social, bots, ratings, game summaries — a **read-model + registry, never an arbiter** |
| Blobs (opt-in / later) | **R2** (§5.4) | `AVATARS`: profile-photo uploads — v1 code, opt-in per app · `GAME_HISTORY`: future cold tier for old finished games. Local dev simulates R2 free; a *real* bucket (deploy) requires a payment method |
| Push | **FCM**, sent from the Worker/DO | Service-account JWT minted with WebCrypto — ported as-is from `_engine/fcm.ts` |
| Scheduled work | **DO alarms** (turn deadlines — *only*) · **Cron Triggers** (guest purge) | No alarm multiplexer — see §8 |
| Rules | **Pure TypeScript `GameRules`**, unchanged contract | One unit per `schema_version`; optional Dart twin for preview / local bots |
| Token verify | **`jose`** + ~40 lines of Firebase claim checks | Deliberately not `firebase-auth-cloudflare-workers` (unofficial, low adoption) |

---

## 2. Repos & packages

Two repos, one contract artifact between them: **`openapi.json`**, generated in the server
repo and vendored into the Dart repo for codegen.

### 2.1 `eigen-server` — TS pnpm monorepo (new)

```
eigen-server/
  packages/
    rules/      @eigen/rules      the implementor contract (types only)
    kernel/     @eigen/kernel     pure commit() → CommitPlan. No I/O, no platform.
    server/     @eigen/server     everything that deploys: DO + routes + D1 (+ opt-in R2)
    testkit/    @eigen/testkit    twin-fixture runner + runtime scenarios + leak/hibernation tests
  examples/
    rps/                          first implementor (simultaneous-move — hardest case first)
```

Four packages, three boundaries that matter: **contract vs engine** (`rules`/`kernel` —
implementors pin the contract; kernel internals churn freely), **pure vs platform**
(`kernel`/`server` — kernel's package.json never lists `workers-types`, so purity is
enforced by the module graph, not discipline), **prod vs dev** (`server`/`testkit`).
A DO class is exported from the same worker script — one bundle, one deploy — so
DO/routes/D1 are folders inside `server` (`src/do`, `src/routes`, `src/d1`), not packages;
that split models a separation Cloudflare itself doesn't have. (If a future self-host
ever wants the DO logic behind a different HTTP layer, the re-split follows the existing
folder lines.)

**`@eigen/rules`** — the one package a game author must understand. Ported near-verbatim
from `_types/engine.types.ts`: `GameRules` (six hooks: `initialState`, `applyAction`,
`applyLifecycle`, `computeObservation`, `ratingPool`, `botSeatable`), `GameModule` (the
`versions` map keyed by `schema_version`), `Envelope`, `OutcomeEntry`, `HookContext`,
`IllegalMoveError`, the `Rng` interface, `passthroughObservation`. Schema slots are typed
against **Standard Schema** (implementors bring Zod/Valibot/ArkType). Dep:
`@standard-schema/spec` (types only).

**`@eigen/kernel`** — `commit(input) → CommitPlan | Rejected` (§3.1). Contents: `timing.ts`
(deadline precedence chain, bank deduction, Fischer increment, the **single grace constant**
— ports of `compute_next_deadline` / `deadline_expired` / the clock logic in
`engine_commit_action`), `observe.ts` (per-seat projection fan-out, cause cues, replay
projection), `rng.ts` (`rand-seed` sfc32 derived from `'<seed>:<version>'`, identical to
today), `ratings.ts` (OpenSkill, multi-seat bot collapse, `RatingDelta[]`), `guards.ts`
(`assertHookState`, `assertBudgetPending`, `assertForfeitPending`,
`assertPendingIdentified`, and the **same-view rule** §3.5). Deps: `openskill`, `rand-seed`,
`@eigen/rules`. Zero platform imports, injected clock — forever.

**`@eigen/server`** — the deployable, in three folders:

- `src/do` — the `GameDO` class: its drizzle SQLite schema (§5.1, applied via the
  `durable-sqlite` migrator during lazy init), the gated `handle()` loop
  (§3.4), waiting-room command handlers (§4.2), lazy init from D1 via
  `blockConcurrencyWhile`, hibernating WebSocket accept + version-ordered fan-out + range
  fetch, the deadline alarm, the finish sequence (§4.5: compaction + D1 apply — finished
  games stay in the DO, §4.6; the later cold-tier sweep will live here too, but ships no
  v1 code).
- `src/routes` — `createEngine(config)`, the hono app factory an implementor exports.
  `auth/firebase.ts` (jose `createRemoteJWKSet` against Google's securetoken JWKS + claim
  checks: `iss`/`aud` = project, `sub` non-empty, `exp`, `sign_in_provider === 'anonymous'`
  for guest gating; provisions the D1 user row on first sight of a token). Routes: commands
  (mint `Command`, route to DO), reads (lobby, friends lobby, history, `players?ids=`,
  search, bots catalog, replay), social writes, avatar upload (opt-in — §5.4), device
  installations,
  account-deletion orchestration, cron handlers (in-band — no HTTP self-auth),
  `bot/action` (HMAC), the gated `admin/games/:id/history`, and the link group (§2.4:
  `.well-known` for both platforms + `/j/:shortCode` landing, driven by `deepLink`
  config). OpenAPI via
  `@hono/zod-openapi`; a script emits `openapi.json`. `fcm.ts` and `bot_auth.ts` ported
  from `_engine/`.
- `src/d1` — drizzle schema (§5.2) + migrations (generated by drizzle-kit, applied by
  `wrangler d1 migrations apply` — **engine-owned end to end**; the vendored-SQL migration
  sync CLI from the Supabase era is dead; migration files ship as the
  `@eigen/server/migrations` subpath export) + query helpers shared by route reads and DO
  effects (summary upsert, outbox apply with `finish_id` dedupe, the rating CAS).

Deps: `hono`, `@hono/zod-openapi`, `zod`, `jose`, `drizzle-orm`, `@eigen/kernel`.

**`@eigen/testkit`** — the twin-fixture runner (node/vitest port of the Deno runner — same
JSON fixture format, existing fixtures work unchanged), the runtime scenario harness (JSON
command arrays replayed under `vitest-pool-workers`), the leak test, the hibernation
assertion (§11).

### 2.2 `eigen_engine` — Dart repo (this repo, evolves)

`supabase/` is deleted at parity. The package splits in two:

- **`eigen_client`** — transport only: Firebase Auth wiring, OpenAPI-generated command/read
  methods (dio; hand-write the thin client if codegen fights), and the **frame stream**
  (WebSocket, version-ordered delivery, gap recovery by range fetch, reconnect resync,
  roster-snapshot handling pre-start). Pure Dart.
- **`eigen_flutter`** — everything else in `lib/` today: Riverpod shell, lobby, waiting
  room, game screen, history, replay scrubber, friends, settings, account deletion, push
  wiring, timing widgets, local-bot driver.

Unchanged: every screen, the Dart `GameModule` contract (`buildContent`, twins,
`LocalBot`), theming, persistence, twin fixtures in Dart CI.

### 2.3 What an implementor ships

Server — the entire deployable:

```ts
// bravado-server/src/index.ts
import { createEngine, GameDO } from '@eigen/server';
import { gameModule } from './rules';   // GameRules per schema_version — same contract as today

export default createEngine({ module: gameModule });
export { GameDO };
```

plus `wrangler.jsonc` (bindings from a template), `wrangler secret put`, `wrangler d1
migrations apply`, `wrangler deploy`. Client: depend on `eigen_flutter`, register the Dart
`GameModule` + `BoardView`, `flutterfire configure`. The implementor writes **rules TS, a
board widget, and an optional Dart twin** — nothing else. Packages are consumed from a
private GitHub Packages npm registry (OSS-shaped, private-first).

### 2.4 Web & deep linking — the game worker is the link host

The deployed game worker carries a **static assets binding** and serves three things from
one host:

1. **The API + GameDO** under `/api/*` — everything above.
2. **`/.well-known/assetlinks.json` + `/.well-known/apple-app-site-association`** —
   worker-generated (both platforms, correct content types) from `createEngine` config:
   the implementor supplies Android package + SHA-256 fingerprints and Apple team/bundle
   ID. One source of truth; no hand-maintained JSON files.
3. **Join/share landing pages** — `/j/:shortCode` rendered by a worker route that reads
   the D1 summary (game name, host, open seats) for real OG tags, then deep-links into
   the app with a store fallback. Everything else (screenshots, marketing) is plain
   static assets in `public/`.

So **deep-link host == API host**: one custom domain, one cert, one deploy, and the share
URL users see is the host the app already talks to. Free-tier synergy: static-asset
requests are **unmetered** (they don't count toward the 100k req/day cap); only the
`run_worker_first` paths (`/api/*`, `/.well-known/*`, `/j/*`) invoke the worker.

Host story for implementors: bought a domain → zone + `custom_domain` on the worker; no
domain → the free `<name>.<account>.workers.dev` subdomain. App Links and Universal Links
accept any HTTPS host, so links work on day 0 either way — the opinionated path is
"deploy the engine worker, your links already work."

House estate (`eigeninteractive.com`): apex → Docusaurus engine-docs worker (later;
Workers-with-assets is CF's recommended path over Pages, which is in maintenance);
`bravado.eigeninteractive.com` → the Bravado game worker's custom domain (an exact custom
domain out-ranks `eigeninteractive-web`'s `*.eigeninteractive.com/*` wildcard route — no
change needed there). `eigeninteractive-web` keeps `strategy` until the Supabase app
retires, then shrinks to the apex page until Docusaurus replaces it. Known gap it never
had: no AASA file (no iOS Universal Links for Strategy) — the engine route group emits
both platforms from the start.

Implementation cost: a route group + config fields in `@eigen/server`
(`src/routes/links.ts`, `deepLink` on `createEngine`) — the four-package layout holds.

---

## 3. The core

### 3.1 The kernel is pure — this is the crown jewel

```ts
// @eigen/kernel — zero I/O, zero platform imports, deterministic.
export function commit(input: {
  game: GameRow;        // config, timing mode, rated, schema_version
  state: StateRow;      // state + version + clocks + pending_players
  roster: Seat[];
  intent: Intent;       // action | lifecycle (timeout/forfeit) | start
  now: number;          // injected — never Date.now()
  rules: GameRules;     // the implementor's version unit
}): CommitPlan | Rejected;

export type CommitPlan = {
  nextState: StateRow;
  frames: ObservationFrame[];   // per seat, already projected — no raw state escapes
  outcomes?: Outcome[];
  ratings?: RatingDelta[];      // computed here, written by the applier
  deadline: number | null;      // what the DO must arm (already includes grace)
  effects: Effect[];            // pushes to send, server bots to wake
};
```

Timing, banks, grace, ratings, hidden-info projection, timeout resolution, and the
same-view rule are unit-testable in milliseconds with no infrastructure. The kernel is also
the insurance policy: if Cloudflare ever becomes untenable, the rules *and* the engine move
— only the host package (`@eigen/server`) does not.

### 3.2 The Durable Object is the game's database

One DO per `game_id`. A live game's transitions never touch a shared database. Three things
follow, and they are the reason for the whole design:

- **Serialization is free** (with one rule — §3.4). Two players acting in the same round
  cannot race; the `FOR UPDATE` chokepoint, the stale-retry loop, and the three-way
  timeout race all cease to exist.
- **Timers are exact.** One alarm at `turn_deadline + grace` fires in the actor that owns
  the state. The client-side expiry nudge, the pg_cron sweep, pg_net, and the Vault secret
  it authenticated with are all deleted with no replacement.
- **Frames come from the socket-holder**, in version order, by construction.

> **Store a transition as ONE row** — `{state, frames[], action, timing}` — not the
> four-table relational shape. A per-game database has no reason to normalize, and the
> one-row shape is a ~3.5× difference in the binding free-tier limit (§10).

### 3.3 Commands, not closures

A Worker always fronts a DO. What crosses that boundary is **data**:

```ts
type Command =
  | { kind: 'join' | 'leave' | 'cancel' | 'start';
      gameId: string; commandId: string; actor: Principal }
  | { kind: 'add-bot';   gameId: string; commandId: string; actor: Principal; botId: string }
  | { kind: 'action';    gameId: string; commandId: string; actor: Principal;
                         seat: number; expectedVersion: number; data: unknown }
  | { kind: 'lifecycle'; gameId: string; commandId: string; actor: Principal | null;
                         type: 'timeout' | 'forfeit' | 'auto_forfeit'; seat?: number };
```

- **Authorization happens at the edge.** The Worker verifies the Firebase token and runs
  every *policy* check (guest gating, friends-access via D1, schema gate, `botSeatable`,
  rated validation) **before minting the command** — a command is self-contained and
  pre-authenticated. All D1 reads a decision needs happen here, never inside the DO's gate.
- **Commands are values** — loggable, retryable, replayable. A CI fixture is a JSON array
  of commands.
- **Every command carries a `commandId`**, deduped at the DO (§3.6).
- **Sockets are routed, not sent**: the Worker forwards the upgrade request; the DO accepts
  the socket itself.

### 3.4 The input gate serializes — provided you obey one rule

> **⚠️ Never await non-storage I/O between reading and writing DO storage.** A `fetch` to
> D1, R2, FCM, or a bot webhook opens the input gate and lets another command interleave.

The shape of `handle()` is therefore fixed:

```ts
async handle(cmd: Command): Promise<Result> {
  if (this.#seen(cmd.commandId)) return this.#replay(cmd.commandId);   // storage
  const snap = this.#load();                                            // storage
  const plan = commit({ ...snap, intent: cmd.intent, now: Date.now(), rules: pick(snap) });
  if ('rejected' in plan) return plan;

  this.#apply(plan);                    // storage — ONE SQLite transaction. Gate held.
  // ── post-commit: interleaving is harmless from here ──
  this.#fanout(plan.frames);            // sockets we hold
  await this.ctx.storage.setAlarm(plan.deadline);   // deadline is the ONLY alarm client
  this.ctx.waitUntil(this.#effects(plan));          // D1 summary, FCM, bot wake — single attempt
  return { ok: true, frame: plan.frames[cmd.seat] };
}
```

Read → compute → write, no network in between. Every network effect happens after the
SQLite commit, where an interleaved command simply reads already-committed state.

### 3.5 Simultaneous moves — the same-view rule

Serialization removes torn writes, but a policy is still needed when a command arrives with
a stale `expectedVersion` (someone else committed while it was in flight):

> A stale-version action is **accepted iff the acting seat's own projected observation is
> unchanged** between `expectedVersion` and the current version — comparing the stored
> frames' `data` + the seat's observed `pending_players` as canonical JSON, ignoring
> version/timing bookkeeping. Otherwise it is rejected with the "board updated" error.

Rationale: the observation *is* the seat's decision basis — that is the whole
hidden-information model. Identical view ⇒ the intent transfers soundly (and `applyAction`
still validates legality against the true current state). Changed view ⇒ the conflict is
genuine, and "board updated — try again" is literally true.

Consequences:

- **RPS works with zero game code**: an opponent's hidden commit doesn't alter your
  observation, so both submissions land regardless of arrival order.
- **Sequential games are automatically strict**: any opponent move changes your view.
- **The implementor controls the policy implicitly through `computeObservation`** — reveal
  an event and it invalidates pending stale submissions; hide it and they survive. No
  flags, no second encoding of the information model.
- Cheap: the frames are already stored per transition (§5.1); the check is a compare of two
  stored blobs. If the `expectedVersion` row is gone, reject conservatively.

**Versions stay strictly serial.** The rule governs *acceptance only*. Every accepted
action commits as the next version in arrival order — one gapless linear chain. (In an RPS
round at `N`: A commits `N+1`; B, stale at `N` but same-view, commits `N+2`.) Frame streams,
gap recovery, replay, and `'<seed>:<version>'` RNG derivation all assume this.
`lifecycle` commands (forfeit/timeout) skip version checks entirely — unconditional intent,
as today.

### 3.6 Idempotency — two keys, two boundaries

Serialization orders commands; it cannot identify duplicates. Any effect that must happen
exactly once, delivered over a channel that can fail after the effect but before the
confirmation, needs an idempotency key on the receiving side. There are exactly two such
channels:

- **`commandId` (client → DO).** A client retries a POST it never saw the response to. The
  DO keeps a `commandId → response` table; a duplicate replays the stored response —
  including the own-move frame — instead of double-applying (forfeit/join) or spuriously
  rejecting a move that actually landed (action). Dropped with the rest of DO storage at
  finish.
- **`finish_id` (DO → D1).** The finish spans two stores with no shared transaction; the
  D1 apply is keyed on `finish_id` so a re-run (including a manual re-poke — §8) is a no-op.

Everything else is either re-derivable (the D1 summary row) or naturally idempotent
(re-sent frames are discarded by the client's version-ordered stream).

---

## 4. Game lifecycle, end to end

### 4.1 Creation — the one worker-direct write

```
POST /games → worker: validate (timing modes, player counts, access, guest gates,
              ratingPool + rated assertion — all of today's TS policy, verbatim)
            → generate game_id + short_code (D1 UNIQUE + retry loop)
            → INSERT the D1 game row (creator = seat 0, status 'waiting')
            → return { game_id, short_code }.   The DO does not exist yet.
```

D1-first is deliberate: existence and lobby visibility have one source of truth, and a game
nobody joins never wakes a DO. The DO lazily initializes from the D1 row via
`blockConcurrencyWhile` on its first command or socket.

### 4.2 Waiting room — D1 never arbitrates, it only displays

Every post-creation mutation is a `Command` to the DO, serialized by the input gate exactly
like moves. The policy/integrity split is today's "policy in TS, integrity under the lock",
relocated:

| Command | Worker (policy, before minting) | DO (integrity, under the gate) |
| --- | --- | --- |
| `join` | guest-vs-rated gate; friends-access (D1 relationships); schema gate vs `client_schema_version`; by-code resolves `short_code` in D1 | status `waiting`/`ready`; seat free; not already seated; assign `player_index`; `ready` at `min_players` |
| `leave` | — | non-creator; lobby statuses only; compact `player_index`es; demote below `min_players` |
| `cancel` | — | creator-only; lobby statuses only; status → `aborted`; drop DO storage (nothing worth retaining — the D1 row alone serves history lists) |
| `add-bot` | guest rejection; `botSeatable`; schema / `rated_eligible` / server-only / timed invariants | creator-only; seat cap; seat the bot |
| `start` | — | creator-only; `ready`; kernel `initialState` → v0; arm alarm; status `active` |

The D1 summary is updated post-commit via `waitUntil` (fire-and-forget, reconcilable from
the DO). Accepted staleness: the lobby may briefly show a game that just filled; the join
then fails cleanly at the DO ("game full") — the identical UX to today's lobby race.

**Waiting-room realtime.** The client opens the game WebSocket immediately, pre-start — one
socket for the game's whole lifetime. Pre-game, the DO pushes a **full roster snapshot** on
every change: unversioned and idempotent (a reconnect just gets the current snapshot), so
no ordering machinery is needed for a ~200-byte payload. Versioned, gap-recovered frames
begin at `start` (v0). "Player joined" becomes instant instead of poll-driven.

### 4.3 Active play

Unchanged frame protocol — the best idea in the codebase, now transport-native: append-only
per-seat observations; the own-move frame rides the command response; gaps recovered by
range fetch against the DO's stored transitions; reconnect resyncs from the latest frame.
Local bots, the solo gate, and `local-bot-action` port unchanged (the bot-observation read
is the one sanctioned DO read, as today's gated RPC was).

### 4.4 Timing — grace collapses to one constant

The timing model (untimed / per-action / budget banks + Fischer increment, the hook's
per-action `turn_seconds` override, the deadline precedence chain, budget-requires-
sequential) ports from `engine_architecture.md` §3 **semantically unchanged**, as pure
kernel code.

The grace window survives — it compensates network physics (server time is measured at
arrival), which no host change fixes — but it collapses from a three-place race-symmetry
requirement into **one constant in `@eigen/kernel`**:

- the kernel accepts an action while `now <= deadline + grace`;
- the DO arms its alarm at `deadline + grace`.

There is no race to referee: whichever arrives first — the latent action or the alarm —
commits; the loser sees already-advanced state and no-ops. Deleted with no replacement: the
client expiry nudge (`game/expire`, `_deadlineTimer`, `kExpiryTriggerDelay`), the
`internal/expire` sweep, pg_cron, pg_net, `serverless_base_url`, and the Vault
`secret_api_key`. The client's `kServerDeadlineGrace` mirror stays display-only; budget-mode
flag-fall semantics (bounded overrun accepted) carry over verbatim.

On alarm fire: run `applyLifecycle({type:'timeout'})` over the whole pending set through the
same `commit()` path — one identity-less system transition, exactly today's semantics.

### 4.5 Finish — the one hard part

`player_ratings` is global (two of one player's games can finish at once), so the atomic
finish Postgres gave us is not recoverable. What replaces it, **simplified by decision to a
single attempt with a safety net**:

1. **The DO's finish is atomic and authoritative.** One DO SQLite transaction: final
   transition, `status = 'finished'`, per-seat outcomes, computed rating deltas, an
   outbox row with a `finish_id`, and **compaction** — delete the per-seat `frames[]`
   (live-only: fan-out and the same-view compare; replay re-projects from raw state) and
   the command-dedupe rows. The instant it commits, the game *is* finished.
2. **The player never sees "pending."** The deltas ship in the final frame over the socket
   the DO already holds. D1 is not in the user's critical path.
3. **Then:** apply the outbox to D1 (one `batch()`: summary status + outcomes JSON,
   `rating_history` inserts, `player_ratings` CAS) → **only then clear the outbox row**.
   Nothing is copied anywhere: DO storage is **retained** — it *is* the game's history
   (§4.6).
4. **Single attempt, log on failure.** No retry alarm, no reconciliation cron. On any
   failure the DO logs and **keeps the outbox row**. The failure mode is
   "game missing from history lists/leaderboard until re-poked", not data loss; a gated
   admin re-poke re-runs step 3, safe because of `finish_id`. (The alarm remains
   deadline-only.)
5. **The rating write is a CAS.** Read `(mu, sigma, version)`, compute in TS,
   `UPDATE … WHERE version = ?`, recompute on conflict. This *fixes* the documented
   concurrent-rated-finish lost-update bug in the legacy stack (`engine_architecture.md`
   §8) rather than porting it.

The observable seam (a CAS conflict can revise a delta already displayed) requires two of
one player's rated games finishing within milliseconds and self-heals via D1 reads.

### 4.6 Game history & replay — retained in the DO, projected on read

**Finished games stay where they were played.** The DO's SQLite — meta, roster, the full
transitions chain, outcomes, rating deltas — is retained after finish (compacted, §4.5)
and *is* the game's history. Nothing is copied out; the finish sequence has no blob write
and no second failure branch. On Cloudflare this is a first-class pattern, not a
workaround: a DO is an addressable SQLite database that costs nothing while idle except
storage, and "one DO per entity as its permanent database" is platform-endorsed.

**Replay is the live range-fetch path, pointed at a finished game.** The worker owns the
rules module, so the replay endpoint projects on read — `computeObservation(…, isReplay:
true)` per version, with the caller's seat, or `player_index = null` for a
non-participant viewing a public game. Exactly today's EF replay semantics: post-game
hidden-info reveal and viewer replay work *by construction*, and raw state remains
server-only — the single replay endpoint is the only reader, and it gates (finished +
participant-or-public) then projects before returning. It takes a **version range** (the
client pages through, same as live gap recovery), which keeps a single invocation's
projection work comfortably inside even the free plan's 10 ms CPU budget regardless of
game length or rules weight. This widens the §5.2 never-wake-a-DO exception list by one
entry: replay is a deliberate single-game deep read — the same species as live gap
recovery — not the list traffic the rule protects.

**What retention trades away — and the cold tier that buys it back.** Keeping the record
inside a live class costs four system-of-record properties: DOs are **not enumerable**
(an iterate-all-histories job is a D1-driven fan-out, not a bucket `list`); the DO
schema **never freezes** (every migration must stay valid for the oldest finished game,
since the durable-sqlite migrator runs on wake); the record is **mutable by
construction** (a bad deploy *can* touch it — softened by DO point-in-time recovery's
30-day window); and DO storage is ~13× R2's price per GB. All four are fleet-scale
concerns, so the remedy is deferred, not deleted: once on the paid plan (a payment
method exists — the same thing that unlocks R2, §5.4), an age-based **cold-tier sweep**
writes each old finished game as one frozen JSON object to the `GAME_HISTORY` bucket
and drops the DO's storage; replay reads DO-if-present, else R2. The blob is the §5.1
data verbatim:

```jsonc
{
  "game": { /* config, timing, rated, pool, schema_version, … */ },
  "roster": [ /* seats with identity refs */ ],
  "transitions": [ { "version": 0, "state": …, "action": null, "pending": […], "timing": … }, … ],
  "outcomes": [ … ],
  "ratingDeltas": [ … ]
}
```

**Raw history, no frames** — same as what compaction leaves in the DO, so the
reveal/viewer projection logic is identical against either store. Why the cold tier is
R2 and not a D1 blob column: D1 has a **hard 10 GB/database ceiling** (≈ one month of
history objects at target scale) and a 2 MB row cap; R2 is unbounded at ~$0.015/GB-month
with zero egress. History *lists*/lobby/leaderboard never read the DO or the blob — they
read D1 summaries. (KV was considered as a card-free blob store and rejected —
appendix.)

**V1 ships the hot path only (decided 2026-07-16).** No sweep and no DO-vs-R2 read
branching — replay reads the DO, full stop. What makes the cold tier a drop-in later is
four seams v1 *does* build:

1. **The replay contract is store-agnostic.** The client asks the worker for a version
   range and gets projected frames; nothing in the API says where history lives. The
   source can change without a client release.
2. **The read seam is a named interface.** The replay route fetches raw transitions
   through the ~20-line `HistoryStore` interface, which v1 ships with exactly **one**
   implementation (the DO range fetch) and no dispatch logic. The cold tier later adds
   the R2 implementation and a DO-if-present-else-R2 composition behind the same
   interface — the route never changes.
3. **Compaction leaves exactly the blob.** The post-finish DO rows are field-for-field
   the cold-tier object above, so the sweep is a straight serialization — no transform,
   no schema reconciliation at archive time.
4. **The discriminator ships in the schema from day 0.** The D1 games row carries a
   nullable `archived_at` (§5.2) — `NULL` means the history lives in the game's DO,
   which is every row until the sweep exists. V1 never writes or reads it; the sweep
   just starts stamping it. Being data rather than code, it costs nothing to carry.

### 4.7 Account deletion & guest purge

Same semantics as `engine_architecture.md` §22/§25, re-hosted: the worker forfeits the
user's active games via `lifecycle` commands to each DO (rated forfeits apply ratings while
the user row exists), then one D1 `batch()` does cancel/leave cleanup + preserve-vs-delete
exactly per today's table (seat rows kept with null identity → "Deleted User"), then the
Firebase account is deleted via the service-account REST API. The stale-guest purge is a
Cron Trigger running the same path in-band — no HTTP hop, no shared secret.

---

## 5. Data

### 5.1 DO SQLite — the game

| Table | Contents |
| --- | --- |
| `meta` | The game row snapshot (from lazy init) + status + `rng_seed` |
| `roster` | Seats: `player_index`, identity ref (user/bot), type |
| `transitions` | **One row per version**: `{state, frames[], action, pending, deadline, player_times, turn_started_at}` — serves live gap recovery, the same-view compare, and (post-finish) replay. `frames[]` is deleted at finish (§4.5 compaction) |
| `commands` | `commandId → response` dedupe (§3.6) — deleted at finish |
| `outbox` | The finish payload + `finish_id` (§4.5) — cleared once the D1 apply succeeds |

**Retained at finish** — the compacted database *is* the game's history (§4.6), until
the later cold-tier sweep moves it to R2. Dropped at cancel/abort (immediately; the D1
row alone serves history lists).

**Schema is drizzle, same as D1** — defined in `src/do/schema.ts`, applied with
`migrate()` from `drizzle-orm/durable-sqlite/migrator` inside the existing
`blockConcurrencyWhile` lazy init. A second drizzle-kit config (`driver:
'durable-sqlite'`) generates a `migrations.js` bundle that compiles into the worker —
no filesystem, no deploy step; each DO migrates itself on first activation. This buys
typed queries in DO code, one ORM across both stores, and automatic migration of any
live game that survives a deploy which changes the DO schema (raw DDL would have relied
on "games are short-lived"). Cost: drizzle's journal table adds a few rows per game —
noise against the ~70-row §10 budget.

### 5.2 D1 — the global store, and it is small

| Table | Notes |
| --- | --- |
| `users` | **Merged** `users` + `user_profiles` (the split served RLS separation that no longer exists): uid (Firebase), username, email?, display_name, avatar_url, is_anonymous, timestamps |
| `games` | The summary/read-model row: status, access, `schema_version`, config, rated/pool, `short_code` (UNIQUE), min/max players, `participants` **JSON**, `pending_players` + `turn_deadline` (dashboard), `outcomes` **JSON** (at finish), `finish_id`, `archived_at` (nullable; `NULL` = history lives in the DO — stays `NULL` until the §4.6 cold-tier sweep exists), timestamps |
| `relationships` | Friends — canonical pair order + UNIQUE, as today |
| `bots` | Registry, unchanged columns (`is_local`, `webhook_url`, `schema_version`, `rated_eligible`, `config`) |
| `player_ratings` | Per identity per pool: mu, sigma, display, **`version` (CAS counter)** |
| `rating_history` | Immutable per-game log, keyed for the per-user history screen; unique on (`game_id`, identity) *and* carrying `finish_id` |
| `device_installations` | FCM targets (FID-keyed), unchanged |

Deliberate simplifications: `game_outcomes` is **JSON on the games row** (history reads are
"my games + my result" through the participants index — no per-outcome table needed);
**no identity denormalization** into the games row — the batch `players?ids=` endpoint
(today's `app_players` twin) plus the client's SQLite-persisted `playerInfoCacheProvider`
makes identity lookups cache-warm; user search is `LIKE` (D1 supports FTS5 if it ever
matters); `private.app_config` and Vault become `wrangler.jsonc` vars and secrets.

> **Rule: never wake a Durable Object to serve a read.** Lobby, history lists, profiles,
> search, players, bot catalog: Worker → D1. Only commands, the WebSocket, range fetches
> (live gap recovery *and* finished-game replay — §4.6), and the local-bot observation
> touch the DO.

### 5.3 RLS is gone; the kernel is the guarantee

Nothing but the engine touches the data. Hidden-information safety lives entirely in the
kernel: it projects per-seat frames, and **no route exposes raw state** — none is written.
This is a real reduction in safety margin, paid for in tests: the **leak test** (§11)
asserts no response body ever carries an unprojected state field, and it exists before the
first game ships.

### 5.4 R2 — opt-in and later; the engine core needs no payment method

R2 is the one primitive we'd use that **requires a payment method on file even for
free-tier use** — for *real* buckets. Local dev is exempt: `wrangler dev` and
vitest-pool-workers simulate R2 inside `.wrangler/state` with no card, no real bucket,
and no account call, so R2-backed features are built and tested for free. The engine's
*required* path never touches R2 either way — an implementor runs games, replays, and
profiles with no card, ever. Two features pull real R2 in:

| Bucket (dev names) | Binding | When | Contents | Access |
| --- | --- | --- | --- | --- |
| `eigen-avatars-dev` | `AVATARS` | **V1 code, opt-in per app**: the implementor enables profile-photo uploads via an `avatars` config block on `createEngine` (absent → the upload route isn't mounted, no binding needed). Built and tested under local simulation from day 0; the card enters only when deploying with uploads enabled | User avatar images | World-readable — the highest-frequency blob read in the app |
| `eigen-game-history-dev` | `GAME_HISTORY` | **Later**: the §4.6 cold-tier sweep, once on the paid plan (a card exists by then anyway); v1 ships only the single-implementation `HistoryStore` read seam — no sweep, no branching | One frozen raw-history object per old finished game | **Private forever** — raw state carries hidden info (non-negotiable 9); the replay endpoint is the only reader and projects before returning |

**The default avatar costs zero storage anywhere**: `avatar_url` carries the Firebase
provider photo (Google supplies one; Apple doesn't; guests have none — the client
renders initials for those). Photo uploads are a product decision, not an engine
requirement.

If both buckets exist, two-not-one stays forced: **public access in R2 is a bucket-level
switch** (r2.dev or a bucket custom domain — no per-prefix policy), and these datasets
sit at opposite ends of it. Disambiguation: a user's game-history **list** is D1 summary
rows (§5.2); a game's full raw history lives in its DO (§4.6) until the sweep freezes it
into R2, read only by replay either way.

**Avatar serving** (deferred to the client phase): a bucket custom domain requires a CF
zone, which free-`workers.dev` implementors don't have, and the r2.dev URL is
rate-limited / non-production. So v1 serves avatars through a worker route with strong
`Cache-Control`; public-bucket-on-custom-domain is the later optimization for hosts with
a zone. The private/public *split* is decided now precisely so that flip stays a
config change.

---

## 6. Identity — Firebase Auth

Already run for FCM/Analytics/Crashlytics: no new vendor, no new keys.

- **Google + Apple + Anonymous** (Apple is mandatory alongside Google on iOS — Guideline
  4.8; true today as well).
- **`linkWithCredential`** upgrades guest → permanent **preserving the UID** — the entire
  §25 guest lifecycle (generated `player_NNNNN` handle, profile backfill on conversion,
  switch-into-existing-account on `credential-already-in-use`) ports with Firebase doing
  the hard part.
- The ID token's `firebase.sign_in_provider === 'anonymous'` drives every guest gate (no
  rated, no social, no search, local-bots-only) — same checks, same places (worker policy).
- Verification: `jose` `createRemoteJWKSet` against Google's securetoken JWKS (cached per
  isolate) + Firebase claim checks (`aud` = project id, `iss` =
  `https://securetoken.google.com/<project>`, `sub`, `exp`). ~40 lines of our code. Only
  `FIREBASE_PROJECT_ID` is needed to verify; the service-account trio is for FCM sends and
  account deletion.
- A `users` row is provisioned in D1 on first sight of a token (replaces `handle_new_user`).

---

## 7. Push & bots

**FCM** — `_engine/fcm.ts` (WebCrypto service-account JWT) ports as-is; pushes target the
FID as today. Turn/finish pushes are DO post-commit effects; social pushes come from the
worker's social routes.

**Server bots** — unchanged contract: woken post-commit with their observation
(HMAC-signed, `x-wake-signature`), reply via `bot/action` (per-bot key =
`HMAC(BOT_SIGNING_SECRET, bot_id)`, domain-tagged, constant-time verify). **The wake is a
single attempt + error log** — the turn deadline is the designed liveness backstop for a
lost wake (the reason for the server ⇒ timed invariant). All four authorization invariants
(local ⇒ sole human; 2+ humans ⇒ server; rated ⇒ server, no guests; local ⇒ untimed /
server ⇒ timed) enforce at the same two seams as today: worker policy + DO seating.

**Local bots** — the Dart `LocalBot` isolate driver ports unchanged; its observation pull
is a gated DO read (the sanctioned exception, as today's `app_local_bot_observation`).

---

## 8. Failure policy — start simple, keep the data

By decision, there is **no retry machinery** in v1:

| Effect | Policy | Backstop |
| --- | --- | --- |
| Bot wake | 1 attempt, log | Turn deadline → timeout resolves the seat |
| D1 summary upsert | fire-and-forget (`waitUntil`), log | Re-derivable from the DO at any time |
| Finish: D1 apply | 1 attempt, log | **The outbox row is kept on failure** (DO storage is retained regardless — §4.6); gated admin re-poke re-runs the apply, idempotent via `finish_id` |
| FCM push | 1 attempt, log | Push is best-effort by nature |

The alarm is **deadline-only**: no multiplexer, no timers table, and *nothing else may call
`setAlarm`* — a stray call would silently unarm the turn deadline. If retry machinery is
ever added, it must go through a multiplexer; until then, this rule is enforced by
convention and review.

---

## 9. Client — Flutter, opinionated

Auth swaps to `firebase_auth`; the ~22 supabase-touching files collapse into
`eigen_client`'s generated API + hand-written frame stream. Everything downstream of the
transport — screens, providers, timing widgets, local-bot driver, persistence, the Dart
`GameModule` contract — is untouched. The implementor still supplies three things: TS
`GameRules` (server truth), a `BoardView`, and an optional Dart twin for optimistic preview
and local bots.

---

## 10. Cost — free tier from day 0

**We launch on the Workers free plan — with no payment method on file.** Every primitive
the day-0 design uses is on it: SQLite-backed DOs (the only kind we allow), alarms,
WebSocket hibernation, D1, and cron triggers (we use 1 of 5). R2 — the one primitive
that demands a card even for free use — is opt-in (avatars) or later (cold tier), and
its card requirement bites only on real buckets at deploy; local dev simulates R2 free
(§5.4). Zero design or code
differences vs paid — the free tier's
impact is purely operational: **daily hard caps that fail with errors** (reset 00:00 UTC)
instead of pay-as-you-go overage, and a 10 ms Worker CPU budget per invocation (DOs get
30 s on both plans; the one worker-side hot path, replay projection, is paginated — §4.6).

Assumes 2 seats, ~30 actions/game, commands over HTTP, frames over a **hibernating**
WebSocket. Per game: ~45 Worker requests, ~35 DO requests, ~0.2–0.6 GB-s DO duration
(post-commit effects keep the DO awake briefly), ~40 D1 row-writes, ~20–40 KB retained
in the DO after compaction.

| Free limit | Per game | Games/day |
| --- | --- | --- |
| DO — 100k rows written/day | ~70 *(one transition row + one command-dedupe row per action)* | **~1,400** ⟵ binds |
| Workers — 100k requests/day | ~45 | ~2,200 |
| DO — 100k requests/day | ~35 | ~2,850 |
| DO — 13,000 GB-s/day | ~0.2–0.6 *(hibernating)* | ~20k–65k |
| D1 — 100k rows written/day | ~40 | ~2,500 |
| DO SQLite — 5 GB stored *(account-wide)* | ~20–40 KB retained/finished game | ~125k–250k finished games before the cold-tier sweep is needed |

| | Free | Paid ($5 base) |
| --- | --- | --- |
| Capacity | ~1,400 games/day | **~15,000 games/day for ~$10/mo** |
| Idle cost | $0 | $5 |
| At the cap | operations **fail with errors** until 00:00 UTC | metered overage, no failures |

**What breaks at the cap, and why it's safe.** A spike that exhausts the DO row-write
budget makes commits fail loudly mid-game — ugly, but never corrupting: the kernel rejects,
nothing partial lands. A finish whose D1 apply fails on a cap leaves fully recoverable
state by design (§8: the outbox row survives until the apply succeeds, and DO storage is
retained regardless) and
the gated re-poke replays it idempotently after reset. The failure policy absorbs the
free-tier failure mode with no extra machinery.

**Upgrade trigger (ops rule, decided now):** move to paid at sustained **~900 games/day**
(≈ 60 % of the binding cap) **or on the first observed cap error** (Workers Error 1027 or
a DO/D1 storage-write failure) — whichever comes first. The dashboard's daily
rows-written/requests graphs are the meter; no in-app metering in v1.

For a whitelabel fleet this is per-app: N idle apps cost $0/month on free ($5N once
upgraded), vs N × $25/month on the legacy stack. Verified against Cloudflare pricing docs
2026-07 (including the Jan 2026 SQLite-storage billing change). One hard prerequisite, not
an optimization: **WebSocket Hibernation API from the first commit** (a non-hibernating DO
burns ~77 GB-s per 10-minute game — a 13× cost penalty, and ~6 games would exhaust the
free duration budget).

---

## 11. What CI must prove

- **Rules conformance** — the twin-fixture suite (same JSON format as today; TS runner moves
  from Deno to vitest, the Dart runner is unchanged).
- **Runtime conformance** — one scenario suite as JSON command arrays under
  `vitest-pool-workers` against local DO + D1: create, join (incl. last-seat race), leave,
  cancel, start, act, **simultaneous act** (the same-view accept case *and* the
  perturbed-view reject case), timeout, disconnect/resync, forfeit, finish, rate, replay
  (participant, viewer, hidden-info reveal), guest purge, avatar upload (opt-in route,
  against locally-simulated R2).
- **Hibernation assertion** — the DO holds no non-hibernatable state while idle (no
  `setTimeout`, no un-awaited fetches). The one bug that is expensive rather than wrong.
- **The leak test** — no response body ever carries an unprojected state field.
- **Idempotency** — replaying any command or re-running the finish apply changes nothing.

---

## 12. Non-negotiables

1. **Hibernation from the first commit.**
2. **No network I/O between reading and writing DO storage** (§3.4).
3. **Never wake a DO for a read** (exceptions: live range fetch, local-bot observation).
4. **One transition = one DO SQLite row.**
5. **The kernel stays pure** — no I/O, no platform imports, injected clock, forever.
6. **Commands are values**, pre-authorized, carrying a `commandId`.
7. **Every finish is idempotent**, keyed by `finish_id`; **the outbox row is cleared only
   after the D1 apply succeeds** — and DO storage is retained: it *is* the history (§4.6).
8. **Only the deadline path calls `setAlarm`.**
9. **Raw state never leaves the server** — replay projects on read; the retained DO
   history and the future `GAME_HISTORY` cold-tier bucket are server-only, never
   public (§5.4).
10. **The gated admin history/re-poke endpoint ships with the first game.**

---

## 13. What we gave up, with eyes open

| Loss | Mitigation |
| --- | --- |
| **The atomic finish** | The outbox + `finish_id` (§4.5); single-attempt policy backed by storage retention + admin re-poke |
| **RLS as defense-in-depth** | Kernel-level projection **plus** the leak test |
| **SQL-queryable game history** | The admin history endpoint (day one); ad-hoc analytics over live game data is genuinely gone |
| **Postgres expressiveness** (`int[]`, `pg_trgm`, interactive transactions) | JSON columns; `LIKE` (FTS5 later); `batch()` + CAS |
| **PostgREST's generated read API** | Hand-written Worker endpoints — the bulk of the build, producing no new capability |
| **Self-hostability** | Accepted — with a softer edge than first stated: `workerd` (Apache-2.0, the real Workers runtime) runs DOs single-node with disk persistence, so a fork can run the engine on one box at small scale (no distributed durability). The pure kernel keeps any bigger move a transport rewrite. |
| **Vendor risk** (DO billing already changed once, Jan 2026) | The pure kernel; the ~2-package host surface |

---

## 14. Build plan

| Phase | What | Exit criterion |
| --- | --- | --- |
| **0. Spike** (~1 wk) | Hibernating-socket echo game + deadline alarm + finish apply to D1, deployed for real + under vitest-pool-workers | Duration billing confirms hibernation; finish sequence survives forced eviction |
| **1. Kernel** | `@eigen/rules` + `@eigen/kernel`: port pipeline/observation/ratings/timing; same-view rule; grace constant; twin-fixture port | Kernel passes fixtures + timing/grace/same-view unit suites, zero infrastructure |
| **2. Runtime** | `@eigen/server` (do + routes + d1): commands, waiting room, sockets, reads, social, avatars (opt-in upload, local R2), cron, admin endpoints | RPS playable end-to-end under `wrangler dev` |
| **3. Conformance** | Full §11 suite | CI green on every non-negotiable |
| **4. Client** | `eigen_client` (generated API + frame stream) + `firebase_auth` swap + transport rewrite in `eigen_flutter`; RPS Flutter app against a deployed env | Full game on a phone against production CF |
| **5. Cutover** | Bravado starts on `@eigen/*`; delete `supabase/`; archive the Supabase project | Bravado development proceeds on CF only |

---

## 15. Repo setup instructions (CLI-first, one-time)

**The split**: CLI-generate anything that encodes *platform* knowledge (versions, config
formats, compatibility dates) — that's where written-down snippets go stale. Hand-write
anything that encodes *our* architecture (package boundaries, schemas, exports) — no
scaffolder knows it. **When a snippet in this section disagrees with what a CLI emits,
the CLI wins and this doc gets updated.** `pnpm wrangler --help` and the `create-cloudflare`
prompts are ground truth for anything post-snippet.

### Step 0 — Prerequisites

```bash
node --version        # Node 24 (current LTS; anything ≥ the active LTS is fine)
pnpm --version        # pnpm 11.x — pinned by devEngines in root package.json
# Cloudflare account at dash.cloudflare.com (free plan — upgrade per §10 trigger)
```

Wrangler is a repo devDependency run via `pnpm wrangler` — never installed globally, so the
version is pinned per project.

### Step 1 — Root workspace (hand-written; no CLI owns this shape)

```bash
mkdir eigen-server && cd eigen-server && git init
```

Root files: `package.json` (`pnpm init`, then edit: `"private": true`, `"type":
"module"`, `devEngines.packageManager` pinning pnpm 11.x with `"onFail": "download"` —
the modern replacement for the corepack `packageManager` field — and `pnpm -r` fan-out
scripts) · `pnpm-workspace.yaml` (`packages/*`, `examples/*`, plus `allowBuilds` for
`esbuild`/`workerd`/`sharp` — pnpm 11 blocks postinstall build scripts by default and
workerd's binary needs one) · `tsconfig.base.json` (strict, `target ES2024`,
`moduleResolution Bundler`, `declaration` + `declarationMap` for the library packages) ·
`.gitignore` (`node_modules`, `dist`, `.wrangler`, `.dev.vars`) · `.nvmrc` (`24`). These
formats are stable and boring; nothing to learn from a generator.

### Step 2 — `examples/rps` via create-cloudflare (the learning centerpiece)

```bash
pnpm create cloudflare@latest examples/rps
# prompts: Hello World → Worker + Durable Objects + Assets → TypeScript → no git → no deploy
```

Read every file it emits before touching anything: `wrangler.jsonc` is the current config
format with a current `compatibility_date` and today's DO-binding + class-lifecycle
syntax; `src/index.ts` is the canonical worker-exports-DO-class shape (the fact that made
`server` one package). Where C3's output differs from this doc's snippets, C3 is right —
with one known exception: the template still emits the **legacy `migrations` array** for
the DO class, which CF has replaced with the declarative **`exports` field** (see the
target shape below). Both work, but a worker uses one or the other and can't move from
`exports` back to `migrations` — adopt `exports` before first deploy.

As built (2026-07-16), the template also emitted, all keepers: `$schema` pointing at
wrangler's config schema, `observability: { enabled: true }`, `upload_source_maps: true`,
and a `cf-typegen` script (`wrangler types` → `worker-configuration.d.ts`, referenced
from the app tsconfig's `types` — this replaces the legacy `@cloudflare/workers-types`
package). It shipped **no test setup**, so the `vitest-pool-workers` wiring is hand-added
from its current docs (step 6). It also shipped a `.prettierrc` — delete it when biome
lands (step 7).

C3 runs an install inside the new directory, leaving a nested `pnpm-lock.yaml` +
`node_modules` there. Delete both and run `pnpm install` from the root: the workspace
keeps **one lockfile at the root** (pnpm's default — single resolution universe, required
for `workspace:*` links; per-package lockfiles are only for independently-installed
deploy units, which `wrangler deploy` bundling never needs).

Then edit the generated `wrangler.jsonc` **toward this target shape** (diff, don't
replace):

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "rps",
  "main": "src/index.ts",
  "compatibility_date": "<keep C3's>",
  "compatibility_flags": ["nodejs_compat"],
  "observability": { "enabled": true },
  "upload_source_maps": true,
  "durable_objects": { "bindings": [{ "name": "GAME_DO", "class_name": "GameDO" }] },
  // Class lifecycle — replaces the legacy migrations array C3 still emits. Declarative:
  // this states what the class IS (SQLite-backed — free-tier-compatible, one-row
  // transitions), not a history of steps. Renames later: state: "renamed" + renamed_to.
  // Renaming MyDurableObject → GameDO in place is fine while nothing is deployed:
  "exports": { "GameDO": { "type": "durable-object", "storage": "sqlite" } },
  "d1_databases": [ /* paste the block `d1 create` prints (step 3) */ ],
  // R2 (§5.4): AVATARS ships in v1 as opt-in and the example exercises it. The binding
  // works fully under local simulation (wrangler dev / tests) with no card and no real
  // bucket; creating the real bucket for a deploy with uploads enabled is the moment a
  // payment method enters — comment this out to deploy card-free. GAME_HISTORY (cold
  // tier) comes later, with paid.
  "r2_buckets": [{ "binding": "AVATARS", "bucket_name": "eigen-avatars-dev" }],
  "triggers": { "crons": ["0 3 * * *"] },   // guest purge
  // §2.4 — static assets unmetered; only these paths invoke the worker:
  "assets": {
    "directory": "./public/",
    "run_worker_first": ["/api/*", "/.well-known/*", "/j/*"]
  }
}
```

The `"storage": "sqlite"` declaration is load-bearing (though now also mandatory for new
classes — legacy KV storage is closed to new namespaces). The `bindings` entry stays: it
grants the worker `env` access; `exports` governs the class's lifecycle.

### Step 3 — Cloudflare resources (CLI by definition)

```bash
pnpm wrangler login && pnpm wrangler whoami
pnpm wrangler d1 create eigen-dev     # prints the d1_databases binding block — paste it
```

No `r2 bucket create` day 0 (§5.4) — real buckets demand a payment method. The AVATARS
binding still works under `wrangler dev` and in tests (local simulation); the bucket is
created only when deploying with uploads enabled.

### Step 4 — First contact with the dev loop

```bash
cd examples/rps && pnpm wrangler dev   # one process: worker + DO + D1 + simulated R2
```

Curl the hello-world route, then skim `.wrangler/state/` — that's where local D1/DO
state lives, and deleting it is what "reset local state" means in the dev-phase
edit-migrations-in-place convention. (`wrangler dev` replaces the whole Supabase Docker
stack.)

### Step 5 — Package stubs (hand-written; pure our-architecture)

```bash
mkdir -p packages/{rules,kernel,server,testkit}
```

Each gets `pnpm init`, then edit: `"name": "@eigen/<pkg>"`, `"type": "module"`,
`exports` → `dist/`; internal deps use `"workspace:*"`.

### Step 6 — Dependencies

```bash
pnpm add -Dw typescript wrangler \
  vitest @cloudflare/vitest-pool-workers tsup @changesets/cli @biomejs/biome

pnpm --filter @eigen/rules   add @standard-schema/spec
pnpm --filter @eigen/kernel  add openskill rand-seed
pnpm --filter @eigen/server  add hono @hono/zod-openapi zod jose drizzle-orm
pnpm --filter @eigen/server  add -D drizzle-kit
```

No `@cloudflare/workers-types` — legacy; runtime types come from `wrangler types`
(the `cf-typegen` script → `worker-configuration.d.ts`). How `@eigen/server` (a library
with no worker of its own) gets its types is a Phase 2 decision: a minimal types-only
wrangler config run through `wrangler types`, or referencing the example's generated
file in dev.

⚠️ `@cloudflare/vitest-pool-workers` pins a narrow vitest version range, and the C3
template shipped no tests to copy from — wire it from its current docs, don't take
latest vitest blindly.

| Tool | Role |
| --- | --- |
| `wrangler` | Local dev, migrations, secrets, deploys |
| `vitest-pool-workers` | Tests run *inside* workerd against real DO + local D1 |
| `tsup` | Builds `dist/` (ESM + d.ts) for private npm publishing |
| `changesets` | `@eigen/*` versioning (use when Bravado consumes) |
| `biome` | Lint + format |

### Step 7 — Tool configs (own `init` where one exists)

`pnpm biome init` (emits current-format `biome.json`; delete C3's `.prettierrc` from
`examples/rps` at the same time — one formatter). Drizzle-kit has **no** init:
`@eigen/server`'s **two drizzle-kit configs** are hand-written (~8 lines each) — one for
D1 (`dialect: 'sqlite'`, `out: './migrations'` — generate only, applied by `wrangler d1
migrations apply`, identical against local and remote) and one for the DO
(`dialect: 'sqlite'`, `driver: 'durable-sqlite'`, out under `src/do/` — emits a
`migrations.js` bundle the worker imports; §5.1). They must not share an `out` directory.

### Secrets

Local: `examples/rps/.dev.vars` (gitignored) — `FIREBASE_PROJECT_ID` (token verify),
`FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY` (FCM + account deletion only),
`BOT_SIGNING_SECRET`. Production: `pnpm wrangler secret put <NAME>` per environment.

### Verify

```bash
cd examples/rps && pnpm wrangler dev    # hello-world serves
pnpm vitest                              # if the C3 template shipped tests
```

Deferred until needed: GitHub Packages `.npmrc` + publish workflow (when Bravado consumes
`@eigen/*`), `pnpm changeset init`, CI workflow (written alongside the first tests),
Firebase console provider enablement (client phase).

---

## Appendix — rejected alternatives (kept for the next time they're proposed)

**The principle underneath most of them: the outbox is contagious, and its benefits are
not.** Free serialization, a database-free hot path, and per-entity storage that migrates
itself accrue only to a durable per-entity store — i.e., to Durable Objects.

- **Dual-host (Node + Cloudflare), Postgres as system of record** — preserves the atomic
  finish and self-hosting; costs 5–10× the money, doubled CI, and a permanent
  design-to-the-intersection tax. *Flips if* a studio/data-residency customer must run on
  their own infra.
- **DO as coordinator, Postgres as store** — pays the Postgres round trip *and* forfeits
  free serialization (the input gate doesn't cover network I/O): worst of both.
- **Node with in-memory state** — a deploy evaporates live games and corrupts the
  append-only frame contract. **Node with local SQLite** — converts stateless replicas into
  a hand-rolled stateful sharded cluster; that's the problem DOs exist to solve.
- **Firestore as global store** — client-direct reads would delete much of the read API,
  but per-action summary writes cost $8–11/mo at 5k games/day (D1: $0) and the free tier
  caps ~600 games/day; no joins, no substring search. *Flips if* the dashboard stops
  needing per-action freshness.
- **`firebase-auth-cloudflare-workers`** — unofficial, low adoption; `jose` + our claim
  checks instead.
- **Workers KV** — eventually consistent (~60 s propagation), so wrong for anything
  authoritative, and everything staleness-tolerant we have is already covered: config is
  wrangler vars/secrets, small registries are cheap D1 reads, JWKS is cached in-isolate by
  `jose` (Cache API if it ever matters). No niche left between DO (strong consistency),
  D1 (global reads), and R2 (blobs). Reconsidered 2026-07-16 as a card-free game-history
  store (R2 demands a payment method even for free use): rejected again — KV's design
  center is edge-cached *hot* reads, the opposite of cold write-once replay blobs (no
  cache benefit on cold keys, ~60 s visibility gap after finish, 1k writes/day would
  become the finished-game binder, 1 GB storage). Retaining history in the DO (§4.6) is
  both simpler and stronger.
- **Queues / Workflows** (both free-plan-available) — every async spot is already covered:
  effects are declaredly best-effort (§8), and the one must-not-lose job (finish apply) is
  durable via DO storage retention + `finish_id` re-poke — a one-slot queue colocated with
  its state. Adding Queues re-adds the deleted retry machinery and, on free, its 10k ops/day
  would become the capacity binder. Queueing the finish (the ratings/D1 apply) specifically was
  considered and rejected: the enqueue itself can fail (so retained-storage survives, just
  rescoped), and free-tier
  24 h retention (DLQ included) would silently expire the one must-never-lose job that today
  is loudly recoverable forever. *Flips if* partially-deleted accounts appear (→ wrap
  account deletion, the system's only multi-step saga, in a Workflow), FCM batching is
  needed at scale, or — on paid, with its 14-day retention — finish-apply re-pokes become
  recurring toil (→ queue the small D1-apply step only, with a DLQ alert).
- **D1 as the game-history store** — hard 10 GB/database ceiling (~1 month of history
  objects at target scale) and 2 MB row cap; the history lives in each game's DO (§4.6),
  cold-tiered to unbounded R2 later.
- **R2 history write at finish** (the original design) — architecturally sound (inert,
  enumerable, frozen system-of-record blob) but demoted to the *cold tier* (§4.6):
  R2 requires a payment method even for free-tier use, breaking the no-card day-0 story,
  and retention-in-the-DO deletes the copy step plus its whole failure branch. The blob
  design returns verbatim as the age-based sweep once on paid.
- **Convex** — genuine ACID + TS-native reactivity, but no first-class Dart client and an
  awkward fit for per-seat hidden-info fan-out. Recorded because it's the strongest
  outside candidate.
- **Nakama as the base** — ships lobby/friends/leaderboards, but always-on Go + Postgres
  contradicts scale-to-zero, and the hidden-info-first frame model would be bolted on.
