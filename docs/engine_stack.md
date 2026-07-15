# Eigen Engine — Architecture of Record (Cloudflare-native)

> **Decision (2026-07-14, design locked 2026-07-15).** The engine runs **Cloudflare-only**:
> Workers at the edge, one **Durable Object per game** owning that game's state in its own
> SQLite, **D1** for global data, **R2** for archives, **Firebase Auth** for identity.
> No Postgres. No Supabase.
>
> **Two sets of keys: a Cloudflare account and a Firebase project.** Nothing else.
>
> **The constraints that drove it:** fast time-to-first-game, **scale to zero** when idle,
> **~$10/month** at real traffic. The Workers **paid plan ($5/mo) is assumed from day one**
> (the free plan's 10 ms CPU budget is too tight for replay projection).
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
| Edge | **Cloudflare Workers** (hono) | Stateless: verify token (**jose**), serve D1/R2 reads, mint commands, route to DOs |
| Game session | **One Durable Object per game** | SQLite-backed; owns state, roster, sockets, the alarm |
| Global store | **D1** | Identity, social, bots, ratings, game summaries — a **read-model + registry, never an arbiter** |
| Archive / blobs | **R2** | One raw-history JSON object per finished game (replay); avatars |
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
    game-do/    @eigen/game-do    the Durable Object
    worker/     @eigen/worker     hono routes, auth, OpenAPI, FCM, bot HMAC
    d1/         @eigen/d1         drizzle schema + migrations + shared queries
    testkit/    @eigen/testkit    twin-fixture runner + runtime scenarios + leak/hibernation tests
  examples/
    rps/                          first implementor (simultaneous-move — hardest case first)
```

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

**`@eigen/game-do`** — the `GameDO` class: its SQLite schema (§5.1), the gated `handle()`
loop (§3.4), waiting-room command handlers (§4.2), lazy init from D1 via
`blockConcurrencyWhile`, hibernating WebSocket accept + version-ordered fan-out + range
fetch, the deadline alarm, the finish sequence (§4.5), archive to R2 behind a ~20-line
`ArchiveStore` interface.

**`@eigen/worker`** — `createEngine(config)`, the hono app factory an implementor exports.
`auth/firebase.ts` (jose `createRemoteJWKSet` against Google's securetoken JWKS + claim
checks: `iss`/`aud` = project, `sub` non-empty, `exp`, `sign_in_provider === 'anonymous'`
for guest gating; provisions the D1 user row on first sight of a token). Routes: commands
(mint `Command`, route to DO), reads (lobby, friends lobby, history, `players?ids=`, search,
bots catalog, replay), social writes, avatar upload, device installations, account-deletion
orchestration, cron handlers (in-band — no HTTP self-auth), `bot/action` (HMAC), the gated
`admin/games/:id/history`. OpenAPI via `@hono/zod-openapi`; a script emits `openapi.json`.
`fcm.ts` and `bot_auth.ts` ported from `_engine/`. Deps: `hono`, `@hono/zod-openapi`,
`zod`, `jose`, `@eigen/kernel`, `@eigen/d1`.

**`@eigen/d1`** — drizzle schema (§5.2) + migrations (generated by drizzle-kit, applied by
`wrangler d1 migrations apply` — **engine-owned end to end**; the vendored-SQL migration
sync CLI from the Supabase era is dead) + query helpers shared by worker reads and DO
effects (summary upsert, outbox apply with `finish_id` dedupe, the rating CAS).

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
import { createEngine } from '@eigen/worker';
import { GameDO } from '@eigen/game-do';
import { gameModule } from './rules';   // GameRules per schema_version — same contract as today

export default createEngine({ module: gameModule });
export { GameDO };
```

plus `wrangler.jsonc` (bindings from a template), `wrangler secret put`, `wrangler d1
migrations apply`, `wrangler deploy`. Client: depend on `eigen_flutter`, register the Dart
`GameModule` + `BoardView`, `flutterfire configure`. The implementor writes **rules TS, a
board widget, and an optional Dart twin** — nothing else. Packages are consumed from a
private GitHub Packages npm registry (OSS-shaped, private-first).

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
— only the host packages (`game-do`, the platform half of `worker`) do not.

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
| `cancel` | — | creator-only; lobby statuses only; status → `aborted`; **no archive** (no transitions — the D1 row alone serves history); drop DO storage |
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
   transition, `status = 'finished'`, per-seat outcomes, computed rating deltas, and an
   outbox row with a `finish_id`. The instant it commits, the game *is* finished.
2. **The player never sees "pending."** The deltas ship in the final frame over the socket
   the DO already holds. D1 is not in the user's critical path.
3. **Then, in order:** write the R2 archive (§4.6) → apply the outbox to D1 (one `batch()`:
   summary status + outcomes JSON, `rating_history` inserts, `player_ratings` CAS) → **only
   then drop DO storage**.
4. **Single attempt, log on failure.** No retry alarm, no reconciliation cron. On any
   failure the DO logs and **keeps its storage** (outbox row included). The failure mode is
   "game missing from history/leaderboard until re-poked", not data loss; a gated admin
   re-poke re-runs step 3, safe because of `finish_id`. (The alarm remains deadline-only.)
5. **The rating write is a CAS.** Read `(mu, sigma, version)`, compute in TS,
   `UPDATE … WHERE version = ?`, recompute on conflict. This *fixes* the documented
   concurrent-rated-finish lost-update bug in the legacy stack (`engine_architecture.md`
   §8) rather than porting it.

The observable seam (a CAS conflict can revise a delta already displayed) requires two of
one player's rated games finishing within milliseconds and self-heals via D1 reads.

### 4.6 Archive & replay — raw history in R2, projected on read

At finish the DO writes **one JSON object** to R2 (behind the `ArchiveStore` interface):

```jsonc
{
  "game": { /* config, timing, rated, pool, schema_version, … */ },
  "roster": [ /* seats with identity refs */ ],
  "transitions": [ { "version": 0, "state": …, "action": null, "pending": […], "timing": … }, … ],
  "outcomes": [ … ],
  "ratingDeltas": [ … ]
}
```

**Raw history, no frames.** The worker owns the rules module, so the replay endpoint
projects on read — `computeObservation(…, isReplay: true)` per version, with the caller's
seat, or `player_index = null` for a non-participant viewing a public game. Exactly today's
EF replay semantics: post-game hidden-info reveal and viewer replay work *by construction*,
the blob is smaller than N per-seat frame tracks, and raw state remains server-only — the
single replay endpoint is the only reader, and it gates (finished + participant-or-public)
then projects before returning. ~30 sub-millisecond projections per request: trivial on the
paid plan.

Why R2, not a D1 blob column: D1 has a **hard 10 GB/database ceiling** (≈ one month of
archives at target scale) and a 2 MB row cap; R2 is unbounded at ~$0.015/GB-month with zero
egress. History/lobby/leaderboard never read the blob — they read D1 — so R2 costs exactly
one `put` and one `get` in the whole codebase.

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
| `transitions` | **One row per version**: `{state, frames[], action, pending, deadline, player_times, turn_started_at}` — serves live gap recovery, the same-view compare, and the archive |
| `commands` | `commandId → response` dedupe (§3.6) |
| `outbox` | The finish payload + `finish_id` (§4.5) |

Dropped at finish — **only after** archive + D1 apply succeed — or at cancel/abort
(immediately; nothing to archive).

### 5.2 D1 — the global store, and it is small

| Table | Notes |
| --- | --- |
| `users` | **Merged** `users` + `user_profiles` (the split served RLS separation that no longer exists): uid (Firebase), username, email?, display_name, avatar_url, is_anonymous, timestamps |
| `games` | The summary/read-model row: status, access, `schema_version`, config, rated/pool, `short_code` (UNIQUE), min/max players, `participants` **JSON**, `pending_players` + `turn_deadline` (dashboard), `outcomes` **JSON** (at finish), `finish_id`, timestamps |
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

> **Rule: never wake a Durable Object to serve a read.** Lobby, history, profiles, search,
> players, bot catalog: Worker → D1. Finished-game replay: Worker → R2. Only commands, the
> WebSocket, live-game range fetch, and the local-bot observation touch the DO.

### 5.3 RLS is gone; the kernel is the guarantee

Nothing but the engine touches the data. Hidden-information safety lives entirely in the
kernel: it projects per-seat frames, and **no route exposes raw state** — none is written.
This is a real reduction in safety margin, paid for in tests: the **leak test** (§11)
asserts no response body ever carries an unprojected state field, and it exists before the
first game ships.

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
| Finish: R2 archive + D1 apply | 1 attempt, log | **DO storage is kept on failure**; gated admin re-poke re-runs the apply, idempotent via `finish_id` |
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

## 10. Cost

Assumes 2 seats, ~30 actions/game, commands over HTTP, frames over a **hibernating**
WebSocket. Per game: ~45 Worker requests, ~35 DO requests, ~0.2–0.6 GB-s DO duration
(post-commit effects keep the DO awake briefly), ~40 D1 row-writes, one ~40–60 KB R2 object.

| Free limit | Per game | Games/day |
| --- | --- | --- |
| Workers — 100k requests/day | ~45 | **~2,200** ⟵ binds |
| DO — 100k requests/day | ~35 | ~2,850 |
| DO — 100k rows written/day | ~35 *(one transition row)* | ~2,850 |
| DO — 13,000 GB-s/day | ~0.2–0.6 *(hibernating)* | ~20k–65k |
| D1 — 100k rows written/day | ~40 | ~2,500 |

| | Free | Paid ($5 base) |
| --- | --- | --- |
| Capacity | ~2,200 games/day | **~15,000 games/day for ~$10/mo** |
| Idle cost | $0 | $5 |

For a whitelabel fleet this is per-app: N idle apps cost $0–5N/month, vs N × $25/month on
the legacy stack. Verified against Cloudflare pricing docs 2026-07 (including the Jan 2026
SQLite-storage billing change). Two hard prerequisites, not optimizations: **WebSocket
Hibernation API from the first commit** (a non-hibernating DO burns ~77 GB-s per 10-minute
game — a 13× cost penalty), and the **paid plan from day one** (10 ms free-tier CPU is too
tight for replay projection).

---

## 11. What CI must prove

- **Rules conformance** — the twin-fixture suite (same JSON format as today; TS runner moves
  from Deno to vitest, the Dart runner is unchanged).
- **Runtime conformance** — one scenario suite as JSON command arrays under
  `vitest-pool-workers` against local DO + D1: create, join (incl. last-seat race), leave,
  cancel, start, act, **simultaneous act** (the same-view accept case *and* the
  perturbed-view reject case), timeout, disconnect/resync, forfeit, finish, rate, replay
  (participant, viewer, hidden-info reveal), guest purge.
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
7. **Every finish is idempotent**, keyed by `finish_id`; **DO storage is dropped only after
   archive + D1 apply succeed.**
8. **Only the deadline path calls `setAlarm`.**
9. **Raw state never leaves the server** — replay projects on read; the archive is
   server-only.
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
| **0. Spike** (~1 wk) | Hibernating-socket echo game + deadline alarm + finish write to D1/R2, deployed for real + under vitest-pool-workers | Duration billing confirms hibernation; finish sequence survives forced eviction |
| **1. Kernel** | `@eigen/rules` + `@eigen/kernel`: port pipeline/observation/ratings/timing; same-view rule; grace constant; twin-fixture port | Kernel passes fixtures + timing/grace/same-view unit suites, zero infrastructure |
| **2. Runtime** | `@eigen/game-do` + `@eigen/worker` + `@eigen/d1`: commands, waiting room, sockets, reads, social, cron, admin endpoints | RPS playable end-to-end under `wrangler dev` |
| **3. Conformance** | Full §11 suite | CI green on every non-negotiable |
| **4. Client** | `eigen_client` (generated API + frame stream) + `firebase_auth` swap + transport rewrite in `eigen_flutter`; RPS Flutter app against a deployed env | Full game on a phone against production CF |
| **5. Cutover** | Bravado starts on `@eigen/*`; delete `supabase/`; archive the Supabase project | Bravado development proceeds on CF only |

---

## 15. Repo setup instructions (manual, one-time)

### Prerequisites

```bash
node --version        # Node 22 LTS (nvm/mise/asdf)
corepack enable && pnpm --version   # pnpm 10.x, via corepack — no global install
# Cloudflare account at dash.cloudflare.com (paid Workers plan, $5/mo)
```

Wrangler is a repo devDependency run via `pnpm wrangler` — never installed globally, so the
version is pinned per project.

### Skeleton

```bash
mkdir eigen-server && cd eigen-server && git init
mkdir -p packages/{rules,kernel,game-do,worker,d1,testkit} examples/rps
```

Root files: `package.json` (`"private": true`, `"packageManager": "pnpm@10.x"`, `pnpm -r`
fan-out scripts) · `pnpm-workspace.yaml` (`packages/*`, `examples/*`) · `tsconfig.base.json`
(strict, `target es2022`, `moduleResolution bundler`) · `.gitignore` (`node_modules`,
`dist`, `.wrangler`, `.dev.vars`) · `.nvmrc`.

### Dependencies

```bash
pnpm add -Dw typescript wrangler @cloudflare/workers-types \
  vitest @cloudflare/vitest-pool-workers tsup @changesets/cli @biomejs/biome

pnpm --filter @eigen/rules   add @standard-schema/spec
pnpm --filter @eigen/kernel  add openskill rand-seed
pnpm --filter @eigen/worker  add hono @hono/zod-openapi zod jose
pnpm --filter @eigen/d1      add drizzle-orm
pnpm --filter @eigen/d1      add -D drizzle-kit
```

(Each package needs a stub `package.json` first: `"name": "@eigen/<pkg>"`,
`"type": "module"`, `exports` → `dist/`; internal deps use `"workspace:*"`.)

⚠️ `@cloudflare/vitest-pool-workers` pins a narrow vitest version range — match vitest to
its documented supported version, don't take latest blindly.

| Tool | Role |
| --- | --- |
| `wrangler` | Local dev (`wrangler dev` = workerd with emulated DO/D1/R2 — replaces the whole Supabase Docker stack), migrations, secrets, deploys |
| `vitest-pool-workers` | Tests run *inside* workerd against real DO + local D1 |
| `tsup` | Builds `dist/` (ESM + d.ts) for private npm publishing |
| `changesets` | `@eigen/*` versioning (init now, use when Bravado consumes) |
| `biome` | Lint + format |

### Cloudflare resources

```bash
pnpm wrangler login && pnpm wrangler whoami
pnpm wrangler d1 create eigen-dev            # note the database_id
pnpm wrangler r2 bucket create eigen-archives-dev
```

### `examples/rps/wrangler.jsonc`

```jsonc
{
  "name": "eigen-rps",
  "main": "src/index.ts",
  "compatibility_date": "2026-07-01",
  "compatibility_flags": ["nodejs_compat"],
  "durable_objects": { "bindings": [{ "name": "GAME_DO", "class_name": "GameDO" }] },
  // REQUIRED — makes the DO SQLite-backed (free-tier-compatible class, one-row transitions):
  "migrations": [{ "tag": "v1", "new_sqlite_classes": ["GameDO"] }],
  "d1_databases": [{ "binding": "DB", "database_name": "eigen-dev", "database_id": "<from create>" }],
  "r2_buckets": [{ "binding": "ARCHIVE", "bucket_name": "eigen-archives-dev" }],
  "triggers": { "crons": ["0 3 * * *"] }    // guest purge
}
```

The `new_sqlite_classes` line is easy to miss and load-bearing.

### Secrets

Local: `examples/rps/.dev.vars` (gitignored) — `FIREBASE_PROJECT_ID` (token verify),
`FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY` (FCM + account deletion only),
`BOT_SIGNING_SECRET`. Production: `pnpm wrangler secret put <NAME>` per environment.

### Verify

```bash
cd examples/rps && pnpm wrangler dev    # one process: worker + DO + D1 + R2
pnpm vitest                              # once the pool-workers config exists
```

Deferred until needed: GitHub Packages `.npmrc` + publish workflow (when Bravado consumes
`@eigen/*`), `changeset init`, CI workflow (written alongside the first tests), Firebase
console provider enablement (client phase).

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
- **D1 as archive store** — hard 10 GB/database ceiling (~1 month of archives at target
  scale) and 2 MB row cap; R2 is unbounded and read by exactly one endpoint.
- **Convex** — genuine ACID + TS-native reactivity, but no first-class Dart client and an
  awkward fit for per-seat hidden-info fan-out. Recorded because it's the strongest
  outside candidate.
- **Nakama as the base** — ships lobby/friends/leaderboards, but always-on Go + Postgres
  contradicts scale-to-zero, and the hidden-info-first frame model would be bolted on.
