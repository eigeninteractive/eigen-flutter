# Eigen Engine — Architecture of Record (Cloudflare)

> **Decision.** The engine runs **Cloudflare-only**: Workers at the edge, one **Durable
> Object per game** owning that game's state in its own SQLite, **D1** for global data,
> **R2** for archives, **Firebase Auth** for identity. No Postgres. No Supabase. Not
> self-hostable, deliberately.
>
> **Two sets of keys: a Cloudflare account and a Firebase project.** Nothing else.
>
> **The constraints that drove it:** fast time-to-first-game, **scale to zero** when idle,
> **~$10/month** at real traffic. Self-hostability was the only serious argument for a
> portable Node host, and it has been explicitly traded away.

This document merges and supersedes `cloudflare_migration_analysis.md`,
`oss_engine_architecture.md`, and `oss_engine_blueprint.md`. It is the *target*
architecture; `engine_architecture.md` remains the reference for the system as built today.

**Contents.** §1 the stack · §2 what changes from today · §3 the core (kernel, DO, commands)
· §4 data · §5 identity · §6 the finishing transaction · §7 cost · §8 client · §9 repo ·
§10 CI · §11 non-negotiables · §12 what we gave up · §13 rejected alternatives · §14 if we
open-source it.

---

## 1. The stack

| Layer | Choice | Notes |
| --- | --- | --- |
| Client | **Flutter** — opinionated, the only client | `firebase_auth`, FCM, Analytics, Crashlytics — unchanged from today |
| Identity | **Firebase Auth** | Google · Apple · **Anonymous**, with `linkWithCredential` guest→permanent upgrade |
| Edge | **Cloudflare Workers** (hono) | Stateless: verify token, serve global reads, mint commands, route to DOs |
| Game session | **One Durable Object per game** | Owns the game's state in **DO SQLite**; holds hibernating WebSockets; arms alarms |
| Global store | **D1** | users, profiles, relationships, bots, ratings, rating history, game summaries, outcomes, device installations |
| Archive / blobs | **R2** | Finished-game frame history (replay), avatars |
| Push | **FCM**, sent from the Worker | Service-account JWT minted with WebCrypto — already built |
| Scheduled work | **DO alarms** (turn deadlines) · **Cron Triggers** (guest purge, outbox sweep) | |
| Rules | **Pure TypeScript `GameRules`**, unchanged | Plus the optional Dart twin for preview / local bots |

---

## 2. What changes from today

### 2.1 The mapping

| Supabase surface today | Cloudflare replacement | Difficulty |
| --- | --- | --- |
| Edge Function (`engine`, Deno + hono, 4 route groups) | Workers (hono runs natively) | **Easy** — the rules module is pure TS |
| Postgres (jsonb, `int[]`, CHECK/FK/UNIQUE, `pg_trgm`) | **DO SQLite** (game) + **D1** (global) | **Medium** — no arrays, no trigram, no interactive transactions |
| `engine_*` SQL RPCs (`FOR UPDATE` commit chokepoint) | The DO's input gate | **Deleted** — see §2.2 |
| PostgREST (`app_*` RPCs + embedded selects) | Hand-written Worker endpoints | **Hard** — the biggest single chunk of work |
| RLS | Nothing. The kernel is the guarantee (§4.4) | **Hard** — a loss, not a port |
| Realtime (broadcast-from-DB, per-seat topics) | DO WebSockets + Hibernation API | **Medium** — and an upgrade |
| Auth (Google + anonymous guests + upgrade) | **Firebase Auth** (§5) | **Easy** — it does this natively |
| Storage (avatars + RLS) | R2 + Worker-signed uploads | **Easy** |
| `pg_cron` + `pg_net` + Vault | DO alarms + Cron Triggers + Worker secrets | **Easy** — and an upgrade |

The client is the hidden cost: **22 Dart files** import `supabase_flutter` (auth, PostgREST,
RPCs, Realtime, Storage). The transport layer of the app is rewritten; the game code is not.

### 2.2 What gets deleted

Not refactored — **deleted**:

- **The optimistic-lock layer.** The DO input gate serializes per game, so `Stale state:`,
  the "board updated — try again" UX, and the retry-on-stale in the forfeit path all cease
  to exist. Including for simultaneous-move games (RPS, Set, Poker) — an open problem in
  `future_plans.md` that stops existing rather than getting solved.
- **The entire timeout apparatus**: `pg_cron` → `pg_net` → Vault `secret_api_key` →
  `internal/expire` → re-validate under `FOR UPDATE`, plus the 750 ms grace window that must
  be applied identically in three places or the timeout path steals the race from an
  on-time-but-latent submit. One DO alarm replaces all of it, firing at the exact deadline.
  A latency grace survives — in one place.
- **Six migration files of `engine_*` SQL**: `FOR UPDATE` locking, `compute_next_deadline`,
  `deadline_expired`, the commit RPCs. Ordinary TypeScript inside the DO.
- **The Realtime trigger stack**: `realtime.send`, the `AFTER INSERT` triggers, the RLS on
  `realtime.messages`.
- **The 500-concurrent-connection ceiling** on Supabase Pro — the limit we would hit first.
- **The local Supabase Docker stack.** `wrangler dev` is one process.

### 2.3 Timing

There are **no production users**, so the data-migration cost is zero today and rises
monotonically. A live game cannot be moved from a Postgres `FOR UPDATE` chokepoint to a DO
input gate without a maintenance window. If this is happening, it happens **before Bravado
ships**.

---

## 3. The core

### 3.1 The kernel is pure — this is the crown jewel

The current design is already right that *the game is a pure function and the engine is I/O
around it*. Push it one layer up: make the **engine** a pure function too.

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
  deadline: number | null;      // what the DO must arm
  effects: Effect[];            // pushes to send, server bots to wake
};
```

Nothing there touches a database, a socket, or a clock. Consequences:

- Timing, banks, grace, ratings, hidden-info projection, and timeout resolution are
  **unit-testable in milliseconds with no infrastructure**.
- The hardest correctness properties (no hidden-info leak, no free thinking time, idempotent
  ratings) are proved once, at the kernel level.
- It is the **insurance policy**: if Cloudflare ever becomes untenable, the rules *and the
  engine* move. Only the ~350 lines that speak DO/D1/R2 do not.

### 3.2 The Durable Object is the game's database

One DO per `game_id`. A live game's transitions never touch a shared database — state,
per-seat frames, and the action log live in that game's own SQLite. Three things follow, and
they are the reason for the whole design:

- **Serialization is free** (with one rule — §3.4). Two players acting in the same round
  cannot race.
- **Timers are exact.** `alarm(turn_deadline + grace)` fires in the actor that owns the
  state.
- **Frames come from the socket-holder.** The DO commits, then writes to the WebSockets it is
  already holding, in version order, by construction.

> **Store a transition as ONE row.** A per-game database has no reason to normalize. One row
> per version carrying `{state, frames[], action}` instead of four (`game_states` + 2 ×
> `observations` + `actions`). This is a **~3.5× difference in the free tier's binding
> limit** (DO rows written) — see §7.

### 3.3 Commands, not closures

Durable Objects are not publicly addressable: a Worker always fronts them. This is
Cloudflare's own prescribed topology — *"use Workers as the stateless entry point that routes
requests to Durable Objects when coordination is needed. The Worker handles authentication,
validation, and response formatting, while the Durable Object handles the stateful logic."*

What crosses that boundary must be **data**, never a closure:

```ts
type Command =
  | { kind: 'start';     gameId: string; commandId: string; actor: Principal }
  | { kind: 'action';    gameId: string; commandId: string; actor: Principal;
                         seat: number; expectedVersion: number; data: unknown }
  | { kind: 'lifecycle'; gameId: string; commandId: string; actor: Principal | null;
                         type: 'timeout' | 'forfeit' | 'auto_forfeit'; seat?: number };
```

A closure captures live references and cannot be serialized to another isolate. Workers RPC
*will* pass a function across as a stub — that is the trap: the body still executes back in
the Worker, so the DO holds its input gate open across a network round trip. You pay for
serialization and do not receive it.

Three consequences:

- **Authorization happens at the edge.** The Worker verifies the Firebase token and resolves
  the seat *before* minting the command, so the command is self-contained and
  pre-authenticated.
- **Commands are values** — loggable, retryable, replayable. A CI fixture is a JSON array of
  commands (§10).
- **Every command carries a `commandId`**, deduped at the DO. The duplicate-apply risk comes
  from a **Flutter client retrying a POST it never saw the response to**, not from anything
  Cloudflare does. A version check alone would reject the retry — but report a move that
  actually succeeded as a spurious "board updated".

**Sockets are routed, not sent.** A WebSocket cannot be JSON-encoded, so the Worker forwards
the *upgrade request* to the DO, which accepts the socket itself (a 101 from its `fetch`).

### 3.4 The input gate serializes — provided you obey one rule

> **⚠️ Never await non-storage I/O between reading and writing DO storage.**
>
> Cloudflare's *Rules of Durable Objects*: **"Input gates only protect during storage
> operations; `fetch()` allows other requests to interleave, which can cause race
> conditions."** A `fetch` to D1, R2, FCM, or a bot webhook **opens the gate**.

So the shape of `handle()` is fixed:

```ts
async handle(cmd: Command): Promise<Result> {
  if (this.#seen(cmd.commandId)) return this.#replay(cmd.commandId);   // storage
  const snap = this.#load();                                            // storage
  const plan = commit({ ...snap, intent: cmd.intent, now: Date.now(), rules: pick(snap) });
  if ('rejected' in plan) return plan;

  this.#apply(plan);                    // storage — ONE SQLite transaction. Gate held.
  // ── everything below is post-commit: interleaving here is harmless ──
  this.#fanout(plan.frames);            // sockets we hold
  await this.ctx.storage.setAlarm(plan.deadline);
  this.ctx.waitUntil(this.#effects(plan));   // D1 summary, outbox, FCM, bot wake
  return { ok: true, frame: plan.frames[cmd.seat] };
}
```

Read → compute → write, with **no network in between**. Every network effect happens *after*
the SQLite commit, where an interleaved command simply reads the already-committed state and
is correct. Break this rule and two actions can both read version *N*.

---

## 4. Data

### 4.1 DO SQLite — the game

Transitions (one row per version), the roster, the outbox, and the `commandId` dedupe table.
Dropped at finish, after the archive is written.

### 4.2 D1 — the global store, and it is small

Everything inherently cross-game: identity, profiles, friends, bots, **ratings**, rating
history, outcomes, device installations, and a **game summary** row (status,
`pending_players`, `turn_deadline`) so the lobby and the active-games dashboard can query
live games *without waking a DO*.

D1's 10 GB ceiling is a non-issue **because the frames are not here**: ~500 bytes of summary
per game, ~75 MB/month at target scale — a decade inside the limit.

> **Rule: never wake a Durable Object to serve a read.** Lobby, history, profiles, and search
> are Worker→D1. Waking a DO costs a request plus duration. Only the write path and the
> WebSocket touch the DO.

The summary row is written **once per action** (it carries whose turn it is). That write is
post-commit and fire-and-forget via `waitUntil`, reconciled from the DO if it is ever lost.

### 4.3 R2 — the archive

At finish the DO writes its frame history as a single R2 object (~60 KB/game) and drops its
SQLite storage. Replay of a finished game reads the object; replay of a live game reads the
DO. Egress-free, ~$0.015/GB.

### 4.4 RLS is gone; the kernel is the guarantee

Nothing but the engine touches the data, and D1 has no RLS anyway. Hidden-information safety
moves entirely to the kernel: **it projects per-seat frames, and no route exposes raw state.**
There is no code path that *could* serve `state` to a client, because none is written.

This is a real reduction in safety margin versus today, and it is paid for in tests, not
optimism — a conformance test asserting **no response body ever carries an unprojected state
field** must exist before the first game ships.

### 4.5 The engine's HTTP API is the contract — not the database

No PostgREST, no client-direct database access. All client traffic goes through a versioned
Worker API specified in **OpenAPI**, from which the Dart client is generated. The schema
becomes an implementation detail we can refactor freely. (**Not tRPC** — a
TS-inference contract is a dead end with a Dart client.)

The cost is explicit: every `app_*` RPC and every embedded select — lobby, friends lobby,
history with outcomes and rating changes, `app_players`, user search — becomes a hand-written
Worker endpoint plus a generated Dart method. **This is the largest single chunk of work in
the build, and it produces no new capability.**

---

## 5. Identity — Firebase Auth

We already run Firebase for FCM, Analytics, and Crashlytics, so this adds no vendor and no
new keys. It provides the *exact* identity model this engine needs:

- **Google + Apple + Anonymous** sign-in. (Apple is mandatory once Google is offered on iOS —
  App Store Guideline 4.8.)
- **`linkWithCredential`** upgrades an anonymous user to a permanent account **preserving the
  UID** — the guest→permanent flow (`engine_architecture.md` §25), for free. This was the
  single most intricate thing a hand-rolled auth would have had to rebuild.
- The ID token carries `firebase.sign_in_provider === 'anonymous'`, so every `is_anonymous`
  policy gate (no rated games, no `friends` access, no user search) maps across unchanged.
- Verification on a Worker is **~80 lines of WebCrypto** against Google's public certs: no
  Admin SDK, no server-side sessions, no refresh-token rotation, no reuse detection.
- The FCM service account already in our secrets can delete users for the account-deletion
  purge (§22).

A `users` row is provisioned in D1 on first sight of a token, replacing the `handle_new_user`
trigger.

---

## 6. The one hard part — the finishing transaction

`player_ratings` is inherently global (two of one player's games can finish at once and touch
the same row), so it cannot live inside a single game's DO. **The atomic finish that Postgres
gives us today is not recoverable.** What replaces it:

1. **The DO's finish is atomic and authoritative.** One DO SQLite transaction: final state,
   `status = 'finished'`, per-seat outcomes, the computed rating deltas, and an **outbox row**
   with a `finish_id`. The instant it commits, the game *is* finished; nothing downstream can
   un-finish it.
2. **The player never sees "pending."** The DO computed the deltas, so it ships them **in the
   final frame**, over the socket it already holds. Result and rating change land together,
   exactly as today. D1 is not in the user's critical path.
3. **At-least-once delivery, exactly-once effect.** The DO applies the outbox to D1 and
   retries **from its alarm** with backoff. Alarms are durable and DO storage survives
   eviction, relocation, and machine loss — *this is why the pattern is sound here and would
   not be on a box with a local disk.* D1 dedupes on `finish_id`.
4. **The rating write is a CAS.** D1 has no interactive transactions and OpenSkill cannot be
   expressed in SQL: read `(mu, sigma, version)`, compute in TS, `UPDATE … WHERE user_id = ?
   AND pool = ? AND version = ?`, re-read and recompute on conflict. (At scale, a **per-player
   rating DO** serializes this by construction; the CAS loop is far less machinery and is the
   right first move.)
5. **Reconciliation.** Write a `finishing` marker to D1 when the finish begins, clear it on
   apply, and let a Cron Trigger re-poke any game stuck in `finishing`.

**The observable seam:** a CAS conflict can revise a delta after it was already displayed, so
the result screen may briefly disagree with the leaderboard. It needs two of one player's
rated games to finish within milliseconds, and it self-heals (history reads D1).

**The bill:** an outbox table, an alarm retry, a `finish_id` dedupe, a CAS loop, and a
reconciliation sweep. A few hundred lines plus a monitoring surface. **This is the price of
the whole architecture** — it is what the ~$60/month and the self-host story bought.

*(Creation is the mirror problem with a clean answer: write the D1 row **first** — it is the
source of truth for existence and lobby visibility — and let the DO lazily initialize from it
via `blockConcurrencyWhile()`.)*

---

## 7. Cost

Assumes 2 seats, ~30 actions/game, commands over HTTP, frames over a **hibernating**
WebSocket. Per game: ~45 Worker requests, ~35 DO requests, ~0.2 GB-s of DO duration, ~40 D1
row-writes, one ~60 KB R2 object.

| Free limit | Per game | Games/day |
| --- | --- | --- |
| Workers — 100k requests/day | ~45 | **~2,200** ⟵ binds |
| DO — 100k requests/day | ~35 | ~2,850 |
| DO — 100k rows written/day | ~35 *(one transition row)* | ~2,850 |
| DO — 13,000 GB-s/day | ~0.2 *(hibernating)* | ~65,000 |
| D1 — 100k rows written/day | ~40 | ~2,500 |
| DO 5 GB · D1 5 GB · R2 10 GB | ~60 KB archived | ~165k games in R2 |

| | Free | Paid ($5 base) |
| --- | --- | --- |
| Capacity | **~2,200 games/day** | **~15,000 games/day for ~$10/mo** |
| Idle cost | **$0** — nothing is always-on | $5 |
| Firebase Auth | free at this MAU | free at this MAU |

Normalize the DO schema instead of using one transition row and the free ceiling drops to
**~800 games/day** (DO rows written binds). For reference: the current Supabase stack costs
~$65–110/month at 5,000 games/day, ~$25/month idle, and caps Realtime at 500 concurrent
connections on Pro (≈250 games).

**Two hard prerequisites, not optimizations:**

- **WebSocket Hibernation API, from the first commit.** A DO that stays awake holding two
  sockets burns ~77 GB-s over a 10-minute game: the free tier collapses to ~170 games/day, and
  1,000 concurrent games costs **~$175/month instead of ~$6**. A 13× penalty for one missing
  API.
- **10 ms CPU per invocation on the free tier.** A heavy rules engine or a searching server bot
  will exceed it. Paid lifts this to 30 s.

---

## 8. Client — Flutter, opinionated

Two Dart packages:

- **`eigen_client`** — transport only: Firebase Auth wiring, generated OpenAPI command
  methods, and the **frame stream** (WebSocket, version-ordered delivery, gap recovery by
  range fetch, reconnect resync). Pure Dart.
- **`eigen_flutter`** — the app shell: Riverpod providers and the screens that are identical in
  every game — lobby, waiting room, history, replay scrubber, friends, settings, account
  deletion, push wiring.

**The implementor supplies three things:** the TS `GameRules` (server truth), a `BoardView`
widget, and an **optional** Dart twin for optimistic preview and local bots. Keep the twin
optional and small — without it you lose optimistic animation and local bots, and nothing
else. That halves the cost of implementing a game.

The frame protocol is unchanged: append-only per-seat observations, gaps recovered by range
fetch, own-move frame riding the command response. It is the best idea in the codebase and it
is transport-agnostic.

---

## 9. Repo layout

```
packages/
  kernel/       @eigen/kernel     pure commit() → CommitPlan. No I/O, no platform.
  rules/        @eigen/rules      the hook contract implementors write against
  worker/       @eigen/worker     hono routes, Firebase token verify, OpenAPI spec
  game-do/      @eigen/game-do    the Durable Object: SQLite, alarms, hibernating sockets
  d1/           @eigen/d1         drizzle schema + migrations for the global store
  testkit/      @eigen/testkit    rules conformance (twin fixtures) + runtime scenarios
clients/
  flutter/      eigen_client + eigen_flutter
examples/
  chess/  rps/  poker/
```

Validation via **Standard Schema** (Zod/Valibot/ArkType all implement it) rather than
hardcoding Zod.

---

## 10. What CI must prove

- **Rules conformance** — the twin-fixture suite, run by every example game and by every
  implementor in their own CI. (This already exists; keep it.)
- **Runtime conformance** — one scenario suite as a JSON array of commands: create, join,
  start, act, **simultaneous act**, timeout, disconnect/resync, forfeit, finish, rate, replay.
  Run under `wrangler dev` / vitest-pool-workers against a local D1.
- **Hibernation assertion** — the DO holds no non-hibernatable state while idle. The one bug
  that is expensive rather than merely wrong.
- **The leak test** — no response body ever carries an unprojected state field (§4.4).

---

## 11. Non-negotiables

1. **Hibernation from the first commit.** The most expensive thing to get wrong.
2. **No network I/O between reading and writing DO storage** (§3.4). The gate is only free if
   you respect it.
3. **Never wake a DO for a read.**
4. **One transition = one DO SQLite row.** Don't port the relational schema into the DO.
5. **The kernel stays pure.** No I/O, no platform imports, injected clock — forever.
6. **Commands are values**, carrying an already-resolved principal and a `commandId`.
7. **Every finish is idempotent**, keyed by `finish_id`.
8. **The gated admin history endpoint ships with the first game**, not after the first
   incident.

---

## 12. What we gave up, with eyes open

| Loss | Mitigation |
| --- | --- |
| **The atomic finish** | The outbox protocol (§6). Permanent machinery in the least-recoverable code path. |
| **RLS as defense-in-depth** | Kernel-level per-seat projection **plus** the leak test (§10). |
| **SQL-queryable game history** — live state is inside a DO, finished games are R2 blobs | A gated `GET /admin/games/:id/history`, **built on day one**. Ad-hoc analytics over game data is genuinely gone. |
| **Postgres expressiveness** — `int[]`, `pg_trgm` search, interactive transactions | JSON columns; FTS5 or `LIKE` for search; `batch()` + CAS instead of transactions. |
| **PostgREST's generated read API** | Hand-written Worker endpoints (§4.5). The bulk of the build. |
| **Self-hostability** | Accepted. A fork cannot run this without Cloudflare. |
| **Vendor risk** — DOs have no OSS equivalent; DO billing already changed once (Jan 2026) | The pure kernel (§3.1) makes a move a transport rewrite, not a rules rewrite. |

---

## 13. Rejected alternatives

Each was seriously considered. Recorded with the reason it fails and the condition that would
flip it, because each is *reasonable* and will be proposed again.

**The principle underneath most of them — the outbox is contagious.** A finishing write cannot
span a per-game store and a global store, so outcomes and ratings land via an outbox. Once
*any* host has that weaker guarantee, the client and the conformance suite must tolerate it
everywhere. The two-store model's **costs are contagious; its benefits are not** — free
serialization, a database-free hot path, and storage relief accrue *only* to Cloudflare,
because only Cloudflare has a durable per-entity store that migrates itself.

**Dual-host (Node + Cloudflare), Postgres as the single system of record.** The design that
preserves the atomic finish and self-hostability. Rejected because self-hostability was traded
away, and without it the Node host buys nothing while costing 5–10× the money (an always-on
Postgres never scales to zero), doubled CI, a worse failure story (one DB incident takes down
every game), and a permanent design-to-the-intersection tax. *Flips if:* a studio or a
data-residency customer must run this on their own infrastructure.

**DO as coordinator, not database** (Postgres stays the system of record; the DO only
serializes and holds sockets). Rejected because it is the worst of both: you pay the Postgres
round trip *and* you do not get free serialization — the input gate does not cover network
I/O (§3.4), so you would need an explicit mutex anyway.

**Node keeps game state in memory until finish.** Rejected: DO SQLite is durable, a heap is
not. A deploy or crash evaporates in-flight games — and clients have already seen frame *N*, so
a rollback that later produces a *different* frame *N* corrupts the append-only contract that
gap recovery, replay, and rating history rest on.

**Node keeps game state in local SQLite.** Rejected: the file lives on one machine's disk,
which converts stateless replicas into a stateful sharded cluster (game→node routing, fencing,
drain-on-deploy) with no answer for "the box died." That is the distributed-systems problem
Durable Objects exist to solve.

**A second hosted Postgres split by domain (game DB vs identity DB).** Rejected: it is a
*shared* database that happens to be a second shared database — same round trip, no free
serialization, no database-free hot path. It collects the split-finish cost and none of the
benefits, and it cuts through the busiest join in the system (`games ↔ participants ↔ users`).

**Firestore instead of D1 for the global store.** Genuinely tempting: client-direct reads with
security rules would delete most of §4.5 (the hand-written read API), restore defense-in-depth,
and give Flutter offline persistence for free. Rejected on **write cost and free-tier ceiling**:
the dashboard summary is written once per action, so 5k games/day is ~4.5M writes/month ≈
$8–11/month (D1: $0, included), and Firestore's 20k writes/day free quota caps the free tier at
~600 games/day against D1's ~2,500. Also no joins (the friends-lobby `in` limit is 30), no
substring search, and a cross-cloud hop from the DO on every write. *Flips if:* time-to-market
dominates cost, or the dashboard stops needing per-action freshness.

---

## 14. If we open-source it

The infrastructure is not a differentiator — three things are, and the README should lead with
them:

1. **The hidden-information model.** Per-seat projected frames are the *only* channel to a
   client, so a leak is structurally impossible rather than review-dependent. No comparable
   engine makes this a first-class primitive.
2. **The append-only per-seat frame stream.** Live play and replay are the same shape (an
   ordered frame sequence with gap recovery), so replay costs zero compute and animation is a
   property of the protocol.
3. **A first-class Flutter client.** None of the incumbents has one.

**Prior art you will be measured against:** **Nakama** (Apache-2.0, Go, Postgres) already ships
most of our non-game feature list — *"why not Nakama?"* is the first question every evaluator
asks, so answer it above the fold. **Colyseus** (MIT, Node) is the closest architectural cousin.
**boardgame.io** is the closest in spirit and has largely stalled — instructive: a good contract
with a thin ecosystem does not win.

**Conventions worth simply copying:** Apache-2.0 (the patent grant matters). pnpm workspaces +
changesets, publish to npm and JSR. **Three example games, not one** (chess, RPS, poker) — they
are the *proof* that the hook contract generalizes. A `create-eigen-game` scaffolder, because
time-to-first-move is the adoption metric that matters. Ship `@eigen/testkit` as a product: a
conformance suite is what turns a framework into a contract. Docs with a "your first game in 20
minutes" path and a hidden-information guide.

**But note the tension:** an engine that only runs on Cloudflare is an *open-source Cloudflare
template*, not a portable engine, and evaluators will say so. The pure kernel (§3.1) is the
honest answer — the game logic and the engine are portable; the ~350-line host is not.
