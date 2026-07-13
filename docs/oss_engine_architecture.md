# Eigen as an Open-Source Engine — Ideal Architecture (Greenfield)

> **Thesis.** If the goal is an open-source turn-based game engine that *other
> people adopt*, the hosting platform stops being the interesting decision.
> Requiring **Durable Objects** makes the engine un-self-hostable (no OSS
> implementation exists — a fork cannot run it). Requiring **Supabase** makes it a
> Supabase template rather than an engine. Either choice caps adoption in a way no
> amount of elegance recovers. The blessed default is a **stateful Node/Bun server
> + Postgres, `docker compose up`**, with Cloudflare and Supabase as first-class
> *optional* deployment adapters. The product is the **kernel and the contract**,
> not the infrastructure.

Companion to `cloudflare_migration_analysis.md`, which answers the *migration*
question for the existing codebase. This document answers a different one: what
would we build if we started today, with adoption — not migration cost — as the
constraint.

---

## 1. Why stateful-first is the better architecture, not merely the more portable one

Serverless buys scale-to-zero and no-ops. A game session needs **sockets, timers,
locks, and hot in-memory state** — precisely what serverless withholds and what a
long-lived process provides for free.

Everything Durable Objects buy us (serialization, alarms, socket hibernation) a
plain Node process also buys, without the lock-in: an in-process actor per game,
a timer for the turn deadline, and the WebSocket held by the same object that
produced the frame. Cloudflare's real contribution is not the actor model — it is
**globally distributed** actors with automatic hibernation, which matters at
100k concurrent sessions and is irrelevant at 1,000.

Serverless is what makes a turn-based engine complicated. It is the reason the
current design needs `pg_cron` + `pg_net` + a Vault secret to notice a clock ran
out, a `FOR UPDATE` lock to serialize two players, and a database trigger to push
a frame to a socket the server isn't holding. A stateful process needs none of
those.

### The load-bearing design move

> **The database version check is the correctness invariant. The actor is a
> performance optimization on top of it.**

- The commit path always does an optimistic version check (`state.version ==
  expected`) inside a transaction. This works on any Postgres, and it survives a
  mis-routed request during a rolling deploy, a network partition, or two nodes
  briefly hosting the same game.
- A per-game **actor** sits in front and serializes requests, so that conflict
  never actually fires in practice — which is what makes simultaneous-move games
  (RPS, Set, Poker) work without spurious "board updated, try again" errors.

Get that layering right and the actor becomes genuinely swappable — in-process
actor, Durable Object, or a Postgres advisory lock — with **identical
semantics**. That is what makes a `SessionRuntime` port honest rather than a leaky
abstraction. Build the actor as the *only* guarantee and every adapter is a
rewrite; build it as an optimization over a DB invariant and every adapter is a
hundred lines.

---

## 2. The core insight to push harder on

The existing design is already right about the most important thing: **the game is
a pure function, and the engine is I/O around it.** Push it one layer further —
make the *engine* a pure function too.

Today: rules are pure, but the orchestration (read → compute → commit → fan out →
rate → schedule) is smeared across an edge function and a SQL RPC, so it can only
be tested by standing up Postgres.

Ideal: a **pure kernel** that takes everything it needs as an argument and returns
everything it wants done as data.

```ts
// @eigen/kernel — zero I/O, zero platform imports, fully deterministic.
function commit(input: {
  game: GameRow;            // config, timing mode, rated, schema_version
  state: StateRow;          // current state + version + clocks + pending
  roster: Seat[];           // humans + bots, seat indices
  intent: Intent;           // game action | lifecycle (timeout/forfeit) | start
  now: number;              // injected clock — never Date.now()
  rules: GameRules;         // the implementor's version unit
}): CommitPlan;

type CommitPlan = {
  nextState: StateRow;
  observations: ObservationFrame[];   // per seat, already projected
  outcomes?: Outcome[];               // on finish
  ratings?: RatingDelta[];            // computed, not written
  deadline?: { at: number } | null;   // what the scheduler must arm
  effects: Effect[];                  // pushes to send, bots to wake
} | { rejected: RejectReason };
```

Nothing in there touches a database, a socket, or a clock. Consequences:

- The entire engine — timing, banks, grace, ratings, hidden-info projection,
  timeout resolution — is unit-testable in milliseconds with no infrastructure.
- A new deployment target is an **adapter**, not a rewrite: read the rows, call
  `commit`, write the plan, dispatch the effects.
- The hardest correctness properties (no hidden-info leak, no free thinking time,
  idempotent ratings) are provable at the kernel level, once, for all hosts.

This is the crown jewel. Everything else in this document follows from it.

---

## 3. Package layout

```
packages/
  kernel/        @eigen/kernel      pure state machine (§2). No I/O. No platform.
  rules/         @eigen/rules       the hook contract implementors write against
  ports/         @eigen/ports       six interfaces (§4). Types only.
  server/        @eigen/server      hono app over the ports; Web-standard APIs only
  testkit/       @eigen/testkit     conformance suite + twin fixtures
  client-ts/     @eigen/client      generated from OpenAPI + frame-stream client
  adapters/
    store-postgres/     drizzle + Postgres (blessed)
    session-inproc/     in-process actor + timers (blessed)
    session-do/         Cloudflare Durable Object
    session-pglock/     advisory lock, for pure-serverless hosts
    transport-ws/       WebSocket hub (blessed)
    transport-supabase/ Supabase Realtime broadcast
    identity-betterauth/  Google OIDC + guest (blessed)
    identity-supabase/    Supabase Auth
    blobs-s3/           S3/R2/MinIO
    push-fcm/           FCM + APNs
clients/
  dart/          eigen_client       Flutter SDK (generated + frame stream)
examples/
  chess/         baseline: sequential, perfect information
  rps/           simultaneous moves
  poker/         hidden information + chance + multi-placement outcomes
```

**Validation:** target **Standard Schema** (the 2025 spec Zod, Valibot, and
ArkType all implement) rather than hardcoding Zod. Implementors bring their own
validator; you remove a dependency argument from your issue tracker permanently.

**Runtime:** `@eigen/server` is written to **Web-standard APIs only** — `fetch`,
`Request`/`Response`, WebCrypto, WebSocket. That is the WinterTC convergence, and
it is what lets one codebase run on Node, Bun, Deno, Workers, and Supabase Edge
Functions with no per-host build matrix. No `Deno.*`, no `node:*` in the core, no
Workers-only globals.

---

## 4. The six ports

Keep the surface small and boring. Every port a game implementor could plausibly
want to swap, and nothing else.

```ts
interface Store {                 // system of record. Blessed impl: Postgres.
  loadGame(id): Promise<GameSnapshot>;          // game + state + roster, one round trip
  applyPlan(plan: CommitPlan): Promise<Applied>; // ONE transaction, version-checked
  // ...lobby / history / social / ratings reads
}

interface SessionRuntime {        // serialization + liveness for one game
  withGame<T>(gameId, fn: () => Promise<T>): Promise<T>;  // serialized entry
}

interface Transport {             // per-seat frame delivery
  publish(seat: SeatRef, frame: ObservationFrame): void;
  subscribe(seat: SeatRef, socket: WebSocket): void;
}

interface Scheduler {             // turn deadlines, sweeps
  armDeadline(gameId, at: number): Promise<void>;
  cancelDeadline(gameId): Promise<void>;
}

interface Identity {              // who is calling; guest vs permanent
  verify(token: string): Promise<Principal>;   // { userId, isGuest }
}

interface Blobs { /* avatars */ }
interface Push  { /* FCM / APNs */ }
```

`applyPlan` is deliberately **one call, one transaction** — state, observations,
action log, outcomes, and rating deltas commit atomically or not at all. This is
the guarantee the current design gets from Postgres and would have lost under a
DO-owns-state model; keeping it as a *port contract* means no adapter can quietly
drop it.

---

## 5. Data: Postgres, and the client API is *not* the database

**Store = Postgres.** Not SQLite, not D1. Implementors need lobby, history,
leaderboard, and search queries; they need jsonb and arrays and real transactions;
and Postgres is self-hostable and portable across every host on earth. Use
**Drizzle** (or Kysely) for typed SQL and migrations. Ship SQLite/libSQL as an
optional adapter for solo/offline deployments, never as the reference.

**The one thing to throw out from the current design: PostgREST + RLS as the
client API.** For a product it is a superb accelerator. For an engine you ship to
others it is disqualifying:

- It makes the **table shape the public contract**, so you can never refactor the
  schema without breaking every deployed client.
- It couples every client SDK to Supabase-flavored JWTs and a Supabase-flavored
  data layer.
- It splits the server surface in two (some traffic through the engine, some
  straight to the DB), so there is no single place to version, document, rate-limit,
  or audit.

Instead: **all client traffic goes through the engine's own versioned HTTP API**,
specified in **OpenAPI**, from which the TS, Dart, and Swift clients are generated.
The database becomes an implementation detail — which is exactly what lets a user
run it on Supabase, Neon, RDS, or a Postgres container without the engine caring.

Keep **RLS underneath as defense-in-depth**. RLS is a Postgres feature, not a
Supabase feature; it costs nothing in portability and it is the thing that turns a
hidden-information leak from a code review question into a structural
impossibility.

> Corollary: **not tRPC.** Typed-RPC-over-TS-inference is a dead end the moment
> you have a Dart client. OpenAPI-first, generate outward.

---

## 6. Deployment matrix

| | Blessed: container | Cloudflare | Supabase |
| --- | --- | --- | --- |
| Compute | Node/Bun on Fly / Railway / Hetzner / k8s | Worker | Edge Function |
| Session | in-process actor + `setTimeout` | Durable Object + alarms | advisory lock + cron |
| Transport | WS hub in-process | DO WebSockets (hibernating) | Realtime broadcast |
| Store | Postgres (any) | Postgres via Hyperdrive | Supabase Postgres |
| Identity | Better Auth (Google + guest) | Better Auth on Workers | Supabase Auth |
| Blobs | S3 / MinIO / R2 | R2 | Supabase Storage |
| Ops floor | ~$5/mo (Hetzner + Neon free) | ~$5/mo | $0 → $25/mo |
| Self-hostable | **yes, fully** | no (DO is proprietary) | yes (Supabase is OSS, heavy) |

**One blessed path, exercised end-to-end in CI.** The others are adapters that must
pass the conformance kit. If you cannot name the blessed deployment, you have built
a framework for building game engines instead of a game engine.

Scale-out for the blessed path, when it's needed and not before: route by
`game_id` (consistent hash / sticky session) so a game lands on one node; the DB
version check remains the backstop that makes a mis-route safe rather than corrupt.
Cross-node fan-out (spectators, lobby) via Postgres `LISTEN/NOTIFY` or Redis
pub/sub.

---

## 7. Prior art — what you will be measured against

| Project | What it is | Why it matters to us |
| --- | --- | --- |
| **Nakama** (Apache-2.0, Go) | Self-hosted game backend on Postgres: auth, friends, leaderboards, matchmaking, notifications, authoritative match handlers | The elephant. It already ships ~our entire non-game feature list. "Why not Nakama?" is the **first question every evaluator asks** — answer it in the README. |
| **Colyseus** (MIT, Node) | Room-per-match authoritative server, self-hostable, monetized via hosted cloud | The closest architectural cousin — essentially the design recommended here. Validates it. |
| **boardgame.io** (MIT) | Turn-based-first, immutable state, plugins, client/server | Closest in *spirit*, and largely stalled. Instructive: a great contract with a thin ecosystem doesn't win. |
| **Rune/Dusk** (hosted) | Deterministic rollback JS multiplayer | Different bet (realtime rollback), same audience. |
| **PartyKit → Cloudflare Agents**, **Rivet Actors / RivetKit** | Actor-per-entity with pluggable drivers | The ecosystem's settled answer to "DO model without DO lock-in." Our `SessionRuntime` port is that pattern — we'd be *adopting* a convention, not inventing one. |

### The wedge

None of our infrastructure is a differentiator. Three things are, and the README
should lead with them:

1. **The hidden-information model.** Per-seat projected observations are the *only*
   channel to a client — there is no side channel that could leak, so a leak is a
   structural impossibility rather than a review-dependent one. Nobody above does
   this as a first-class primitive.
2. **The append-only per-seat frame stream.** Live play and replay are literally the
   same shape (an ordered sequence of frames), with gap recovery, so replay costs zero
   compute and animation is a property of the protocol.
3. **A first-class Flutter/Dart client.** None of the above has one.

"Turn-based multiplayer backend" alone is a crowded field. Those three are not.

---

## 8. Open-source conventions worth simply copying (2026)

- **License: Apache-2.0.** The patent grant matters for anything commercial-adjacent.
  (MIT is fine and is the JS-ecosystem norm; dual MIT/Apache-2.0 is the Rust norm.
  AGPL only if hosted competitors genuinely worry you — it will cost adopters.)
- **Monorepo** with pnpm workspaces; **changesets** for releases; conventional
  commits; publish to **npm and JSR**.
- **`examples/` with three games, not one.** Chess (baseline), RPS (simultaneous),
  Poker (hidden info + chance + placements). An engine with one example game is read
  as a toy — and three examples that stress different axes are the *proof* that the
  hook contract generalizes.
- **`create-eigen-game`** scaffolder (`npm create eigen-game`). The time-to-first-move
  is the adoption metric that actually matters.
- **The conformance kit is a product.** The twin-fixture idea already in the codebase
  is the right instinct — ship it as `@eigen/testkit` so implementors run it in *their*
  CI. A conformance suite is what turns "a framework" into "a contract," and it is the
  single most underrated artifact on this list.
- **Docs**: Starlight or Docusaurus, with a "your first game in 20 minutes" path,
  a hook-by-hook reference, and a hidden-information guide (the subtlest thing an
  implementor can get wrong).
- **CI** runs the conformance kit against every example on every commit, and
  exercises the blessed deployment end-to-end.
- **Monetization** (if wanted): open-core — OSS engine, paid hosting. The road Nakama,
  Colyseus, and PartyKit all took.

---

## 9. The honest cost of this strategy

Runs-anywhere engines are frequently mediocre everywhere and cost double to maintain.
Three disciplines prevent that:

1. **Keep the port surface at six interfaces.** Every additional seam is a permanent
   tax. Resist "just make the rating system pluggable too."
2. **Bless exactly one deployment** and let CI prove it works. Community adapters pass
   the conformance kit or they are not adapters.
3. **Make the kernel pure and keep it that way.** The moment I/O leaks into the kernel,
   every adapter forks and the portability claim quietly becomes false.

And one thing this design deliberately gives up: the **fastest possible path to a
working product**. Supabase's PostgREST + RLS + Realtime is a genuinely superb
accelerator, and the current codebase is faster to ship *because* it leans on them.
This document optimizes for a different objective — adoption by strangers — and pays
for it in integration code we currently get for free.
