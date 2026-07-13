# Eigen OSS Engine — Concrete Blueprint

> **Premises (given).** No Supabase. **Two blessed deployments: a Node/Bun server
> and Cloudflare Workers + Durable Objects.** Opinionated over configurable —
> Flutter is *the* client, Postgres is *the* database, auth is *built in*.
>
> **The one rule that makes two blessed targets tractable:**
> **a Durable Object is a coordinator, not a database.** Postgres is the system of
> record on *both* targets. The DO serializes, holds sockets, and fires alarms —
> it never owns state. Break this rule and you have two engines with different
> semantics, two test suites, and two sets of bugs.
>
> The rejected alternative — **Cloudflare-only** — is recorded in §11, including what
> blessing Node actually costs (it is not the 200 lines of `host-node`) and the
> "ship CF first, keep the seam" middle path.

Companion to `oss_engine_architecture.md` (the *why*) and
`cloudflare_migration_analysis.md` (the migration question for today's codebase).
This document is the *what* — what actually gets built.

---

## 1. The shape

```
                        ┌──────────────────────────────────────┐
   Flutter client ──────►  @eigen/server  (hono, Web-standard) │
   (HTTP + WebSocket)   │   auth · lobby · social · replay      │
                        │   ─────────────────────────────────  │
                        │   GameSession.handle(command)  ◄──── the only writer
                        │      └─ @eigen/kernel (pure)         │
                        └───────────────┬──────────────────────┘
                                        │  one transaction
                                        ▼
                                    Postgres
```

Two hosts for exactly the same `GameSession`:

| | **Node/Bun** (blessed) | **Cloudflare** (blessed) |
| --- | --- | --- |
| HTTP | hono on `node:http` / Bun.serve | hono on a Worker |
| Session serialization | in-process mutex, one `GameSession` per game in a `Map` | **Durable Object input gate** — one DO per game |
| WebSockets | held by the owning process (sticky-routed by `game_id`) | held by the DO, **Hibernation API** |
| Turn deadlines | `setTimeout` in-process **+ DB sweep on boot/interval** (timers die with the process) | **DO alarm** (durable, exact) |
| Postgres driver | `postgres.js` over TCP | `postgres.js` over TCP **via Hyperdrive** |
| Secrets | env | Worker secrets |
| Blobs | S3 / MinIO | R2 (S3 API) |
| Local dev | `docker compose up` | `wrangler dev` (miniflare) |
| Floor cost | ~$5/mo (Hetzner + Neon free) | ~$5/mo (Workers Paid) |

Everything above the horizontal line in the diagram is **one codebase**, written to
Web-standard APIs only (`fetch`, `Request`/`Response`, `WebCrypto`, `WebSocket`).
No `node:*` imports in core. No Workers-only globals in core.

---

## 2. Why "DO as coordinator, not database"

The tempting Cloudflare design is to let each game's DO own its state in DO SQLite.
Resist it. It buys a few milliseconds and costs you the entire premise:

- **Semantics diverge.** DO-SQLite state means no shared transaction with
  `game_outcomes` and `player_ratings` (which are inherently global tables). You'd
  need an outbox + idempotent apply on Cloudflare and a plain transaction on Node.
  Two correctness models, one of which is much harder.
- **The global reads still need Postgres anyway** — lobby, history, leaderboards,
  search, friends. DO SQLite cannot serve them.
- **Portability dies.** The conformance suite can no longer assert the same
  invariants on both targets.

With Postgres as the system of record on both, the Durable Object is doing what it
is *uniquely* good at — serialized entry, durable alarms, hibernating sockets — and
nothing else. The in-process actor on Node does the same three jobs with a `Map`,
a `setTimeout`, and a socket list. The `GameSession` code above them is byte-for-byte
identical.

> **The invariant that makes both safe:** the commit is version-checked inside the
> Postgres transaction. The actor (DO or in-proc) makes conflicts *not happen*; the
> version check makes a conflict *harmless* if it somehow does — during a rolling
> deploy, a mis-route, or a DO relocation. Serialization is an optimization; the DB
> check is the guarantee.

---

## 3. Repo layout

```
packages/
  kernel/          @eigen/kernel     pure commit(input) → CommitPlan. No I/O.
  rules/           @eigen/rules      the hook contract implementors write
  session/         @eigen/session    GameSession.handle(command) — platform-free
  server/          @eigen/server     hono routes, auth, OpenAPI spec
  store-postgres/  @eigen/store      drizzle schema + applyPlan (one transaction)
  testkit/         @eigen/testkit    rules conformance + runtime conformance
  host-node/       @eigen/host-node      Map + mutex + setTimeout + WS + sweeper
  host-cloudflare/ @eigen/host-cf        Worker + DO (input gate, alarm, hibernation)
clients/
  flutter/         eigen_flutter     the client. Auth, streams, Riverpod, widgets.
examples/
  chess/           sequential, perfect information
  rps/             simultaneous moves
  poker/           hidden info + chance + placements
create-eigen-game/ npm create eigen-game
```

Nine packages, two hosts, one client. If a tenth package appears, it should be an
example.

---

## 4. The three layers, concretely

### 4.1 Kernel — pure, zero I/O

```ts
// @eigen/kernel
export function commit(input: {
  game: GameRow;          // config, timing mode, rated, schema_version
  state: StateRow;        // state + version + clocks + pending_players
  roster: Seat[];
  intent: Intent;         // {kind:'action'|'lifecycle'|'start', ...}
  now: number;            // injected — never Date.now()
  rules: GameRules;       // the implementor's version unit
}): CommitPlan | Rejected;

export type CommitPlan = {
  nextState: StateRow;
  frames: ObservationFrame[];      // per seat, already projected — no raw state escapes
  outcomes?: Outcome[];
  ratings?: RatingDelta[];         // computed here, written by the store
  deadline: number | null;         // what the host must arm
  effects: Effect[];               // pushes to send, server bots to wake
};
```

Timing, banks, grace, ratings, hidden-info projection, timeout resolution: all of it
testable in milliseconds with no database. This is the whole engine; the rest is
plumbing.

### 4.2 Session — platform-free, the only writer

```ts
// @eigen/session
export class GameSession {
  constructor(private deps: { store: Store; bus: Bus; sched: Scheduler; rules: GameModule }) {}

  async handle(cmd: Command): Promise<Result> {
    const snap = await this.deps.store.loadGame(cmd.gameId);        // 1 round trip
    const plan = commit({ ...snap, intent: cmd.intent, now: Date.now(), rules: pick(snap) });
    if ('rejected' in plan) return plan;

    await this.deps.store.applyPlan(plan);                          // ONE transaction
    this.deps.bus.fanout(plan.frames);                              // sockets we hold
    await this.deps.sched.arm(cmd.gameId, plan.deadline);           // alarm / setTimeout
    await dispatch(plan.effects);                                   // pushes, bot wakes
    return { ok: true, frame: plan.frames[cmd.seat] };              // own-move frame rides the response
  }

  attach(socket: WebSocket, seat: SeatRef) { this.deps.bus.attach(socket, seat); }
}
```

### 4.3 The command boundary — why not closures

The port that reads best is the one that cannot work:

```ts
interface SessionRuntime {
  withGame<T>(gameId: string, fn: () => Promise<T>): Promise<T>;   // ✗
}
```

On Node it is perfect: take a mutex keyed by `gameId`, run `fn`, release. On
Cloudflare it is impossible — and **the plausible fix is worse than the failure.**

A JS closure is not data. `fn` captures live references — the connection pool, the
request context, the socket list, `this`. There is no code mobility in JS: a closure
cannot be serialized and shipped to a Durable Object, which lives in a different
isolate and likely a different machine. Workers RPC *will* let you pass a function
across as a stub, which is the trap: the DO can call it, but **the body still executes
back in the Worker**. The DO then holds its input gate open across a network round trip
while the real work happens somewhere else — you have paid for serialization and not
received it, the gate's atomicity guarantee has become a lie, and you have opened a
deadlock window. The abstraction does not leak; it inverts.

So what crosses the boundary must be **data**, and the code that interprets it must
exist on **both sides** — `GameSession` is bundled *into* the DO, and what travels is a
value:

```ts
type Command =
  | { kind: 'start';  gameId: string; commandId: string; actor: Principal }
  | { kind: 'action'; gameId: string; commandId: string; actor: Principal;
      seat: number; expectedVersion: number; data: unknown }
  | { kind: 'lifecycle'; gameId: string; commandId: string;
      actor: Principal | null; type: 'timeout' | 'forfeit' | 'auto_forfeit'; seat?: number };
```

Four consequences follow. They are the actual payoff — Cloudflare's constraint merely
forces a shape that is better on Node too.

**Authorization moves to the edge, explicitly.** A closure would have implicitly
captured the request — headers, JWT, socket. A command cannot, so the principal and the
seat must be **resolved before the command is minted** and carried inside it. The
command is self-contained and pre-authenticated, which is exactly what makes the
session relocatable.

**Commands are values, so they are loggable, replayable, and queueable.** A CI fixture
becomes a JSON array of commands — which is precisely what lets *one* scenario suite run
against both hosts (§8). A closure is opaque: you cannot record it, retry it, or put a
queue in front of it later.

**You inherit an idempotency requirement — and both hosts must honor it.** A Worker→DO
RPC can fail *after* the DO has committed. Retrying that command would double-apply a
move. So every command carries a `commandId`, and `applyPlan` dedupes on
`(game_id, command_id)` with a unique index. Node does not strictly need this (an
in-process call cannot half-fail that way), but it implements it anyway, because
identical semantics is the whole point. **This is the clearest instance of the
intersection tax: Cloudflare's network hop levies a cost that Node then pays forever,
for symmetry.**

**Commands are a wire format, so they need a version policy.** During a rolling deploy
an old Worker will send a command to a new DO, or the reverse. The decode-tolerance
convention (`engine_architecture.md` §24, surface 3b) now governs an *internal* boundary
as well as the client↔server one.

#### Sockets are routed, not sent

A WebSocket cannot be JSON-encoded, so it is the one thing that is never a command. The
host port therefore has two methods, not one:

```ts
interface Host {
  dispatch(cmd: Command): Promise<Result>;                    // data → sent to the owner
  connect(gameId: string, req: Request): Promise<Response>;   // socket → request routed to the owner
}
```

`connect` routes the upgrade request to whoever owns the game and lets **that side**
accept the socket — a 101 returned from the DO's `fetch` on Cloudflare, a handoff to the
in-process session on Node. Any design that tries to unify `dispatch` and `connect` is
fighting both platforms at once.

### 4.4 Hosts

```ts
// @eigen/host-node
const sessions = new Map<string, { s: GameSession; queue: Promise<unknown> }>();
export async function dispatch(cmd: Command) {
  const e = sessions.get(cmd.gameId) ?? spawn(cmd.gameId);
  return (e.queue = e.queue.then(() => e.s.handle(cmd)));   // serialize per game
}
```

```ts
// @eigen/host-cloudflare
export class GameDO extends DurableObject {
  #session = new GameSession(deps(this.env, this.ctx));
  async command(cmd: Command) { return this.#session.handle(cmd); }   // input gate = mutex
  async alarm()               { return this.#session.handle({ kind: 'timeout', ... }); }
  async webSocketMessage(ws, msg) { /* rarely used — client sends commands over HTTP */ }
}
```

Note what the Cloudflare host does *not* need: no cron, no `pg_net`, no Vault secret,
no three-place grace-window symmetry, no optimistic-conflict UX. The Node host needs
one extra thing — a **deadline sweeper**, because `setTimeout` does not survive a
restart: on boot and every 30s, `SELECT game_id FROM game_states WHERE turn_deadline <
now() + grace` and re-arm. That is the single honest asymmetry between the two
targets, and it is ~30 lines.

---

## 5. Auth — build it in. No third party.

**Recommendation: the engine ships its own auth. Social + guest only. No passwords.**

This sounds reckless until you enumerate what you actually need:

- Google sign-in (and **Apple** — App Store Guideline 4.8 requires it once you offer
  Google on iOS).
- Anonymous guests (`player_47213`).
- Guest → permanent upgrade, preserving the `user_id`.
- A token both hosts verify statelessly.
- Account deletion.

And what you *don't*: no passwords, no password reset, no email verification, no magic
links, no MFA. **Every auth horror story is a password story.** Remove passwords and
the remaining surface is small enough to own — roughly 400 lines, and it works
identically on Node and Workers because it is pure WebCrypto.

### The design

```
POST /auth/guest                  → mint user (guest) + tokens
POST /auth/google {id_token}      → verify vs Google JWKS → link or create → tokens
POST /auth/apple  {id_token}      → verify vs Apple JWKS  → link or create → tokens
POST /auth/upgrade {id_token}     → attach provider identity to the CALLER's guest user
POST /auth/refresh {refresh}      → rotate; reuse-detection revokes the family
DELETE /auth/me                   → the §22 purge path
```

- **Access token**: our own JWT, **ES256** (WebCrypto `ECDSA P-256` — available on both
  hosts), TTL 15 min, claims `{ sub, is_guest, ver }`. Verified in-process on every
  request. No DB hit on the hot path.
- **Refresh token**: opaque 32-byte random, stored **hashed** in `sessions`, rotated on
  use, with reuse detection (a replayed token revokes the whole family). TTL 60 days.
- **Provider verification**: fetch Google/Apple JWKS, cache in memory (Workers: cache in
  the module scope + `caches`), verify `iss`/`aud`/`exp`/`nonce`. That's the entire
  OIDC surface you need — you never run an OAuth *flow* on the server, because the
  Flutter client does the native flow and hands you an ID token.
- **Identities table**: `(provider, provider_subject) → user_id`, unique. Upgrade =
  insert a row for the caller's existing guest `user_id`, backfill email/name, flip
  `is_guest = false`. The `user_id` never changes, so games, ratings, and friendships
  survive the upgrade untouched.
- **Signing key** in secrets; publish `/.well-known/jwks.json` so a future service can
  verify without sharing the private key.

### Why not the alternatives

- **Better Auth** — the strongest OSS option, and a reasonable `Identity` adapter. But
  it is session/cookie-centric and Node-shaped; on a Flutter client with a Workers
  backend you fight it. And it brings a schema you don't control into the DB you *do*.
- **Clerk / Auth0 / WorkOS / Stytch** — a hosted, per-MAU dependency in an engine whose
  entire pitch is self-hostability. Contradiction. Keep the `Identity` port so a
  company *can* plug these in; do not make it the default.
- **Keycloak / Zitadel / Logto** — a second server in `docker compose`, and none of
  them make "anonymous guest who later becomes a Google account, same user id"
  pleasant. That flow is the whole thing, and it is 40 lines when you own the tables.

> **Keep the `Identity` port anyway** (`verify(token) → { userId, isGuest }`), so the
> built-in provider is just the blessed implementation, not a hardcoded assumption.
> That's the difference between opinionated and inflexible.

---

## 6. Data — Postgres, and the API *is* the contract

- **Drizzle + `postgres.js`.** Node connects over TCP; Workers connect over TCP **via
  Hyperdrive** (which also gives pooling, which Workers desperately need). Same
  Drizzle query code on both. **Do not use an HTTP-only Postgres driver** — the ones
  that don't support interactive transactions can't express `applyPlan`, and
  `applyPlan` is the atomicity guarantee.
- **`applyPlan` is one transaction**: `game_states` + `observations` + `actions` +
  `game_outcomes` + `player_ratings`, version-checked, or nothing. Both hosts. This
  is the contract the whole engine rests on.
- **No PostgREST. No client-direct database access.** All client traffic goes through
  the engine's versioned HTTP API, specified in **OpenAPI**, from which the Dart client
  is generated. The schema is now an implementation detail you can refactor freely.
- **No tRPC** — a TS-inference-based contract is a dead end with a Dart client.

### Drop RLS — deliberately

With no PostgREST, the only thing that touches the database is the engine. RLS would
be defending against your own code, and it would require threading per-request claims
into every connection (awkward through a pooler, awkward from a DO). The hidden-info
guarantee moves where it belongs: **the kernel projects per-seat frames and the API
never returns raw state** — there is no code path that *could* serve `game_states.state`
to a client, because no route exposes it. Back it with a `testkit` conformance test
that asserts no response body ever contains a non-projected state field.

This is the one place this design gives up a real safety net that the current codebase
has. It's the right trade for portability, but it must be paid for in tests, not
optimism.

---

## 7. Client — Flutter, opinionated, batteries included

Ship two Dart packages:

- **`eigen_client`** — transport only: auth (Google/Apple/guest + refresh + secure
  storage), generated OpenAPI command methods, and the **frame stream** (WebSocket +
  version-ordered delivery + gap recovery by range fetch + reconnect resync). Pure
  Dart, no Flutter.
- **`eigen_flutter`** — the opinionated app shell: Riverpod providers
  (`gameFramesProvider`, `lobbyProvider`, `ratingsProvider`, `friendsProvider`) and
  the screens that are identical in every game — lobby, waiting room, history, replay
  scrubber, friends, settings, account deletion, push wiring.

**The implementor supplies exactly three things:** the TS `GameRules` (server truth),
a `BoardView` widget, and an optional Dart twin for optimistic preview / local bots.

Make the Dart twin **optional and small**. In the current design it's `previewAction`,
`ratingPool`, and `botSeatable`. Keep it that way, and make the engine fully functional
without it: no twin ⇒ no optimistic animation and no local bots, everything else works.
That halves the cost of implementing a game, which is the number that determines whether
strangers ship one.

The frame protocol stays exactly as designed today — append-only per-seat observations,
gaps recovered by range fetch, own-move frame riding the command response. It is
transport-agnostic and it is the best idea in the codebase; both hosts implement it
identically.

---

## 8. What CI must prove

The failure mode of two blessed targets is that one of them quietly rots. Prevent it
structurally:

- **Rules conformance** (`@eigen/testkit`): the twin-fixture suite, run by every
  example game and by every implementor in their own CI.
- **Runtime conformance**: one scenario suite — create, join, start, act, timeout,
  simultaneous act, disconnect/resync, forfeit, finish, rate, replay — executed
  **twice**, once against `host-node` (testcontainers Postgres) and once against
  `host-cloudflare` (`wrangler dev` / vitest-pool-workers + the same Postgres). Byte-for-byte
  identical expectations. A PR that passes on one host and not the other does not merge.
- **Hibernation assertion**: a CI check that the DO holds no non-hibernatable state
  while idle. Get this wrong and Cloudflare's cost goes from ~$5/mo to ~$175/mo at
  1,000 concurrent games (see the migration analysis) — it's the one bug that is
  expensive rather than merely wrong.

---

## 9. Rules of the road (the things that keep both hosts blessed)

1. **DO is a coordinator, not a database.** Postgres is the system of record on both.
2. **Commands, not closures**, across the session boundary.
3. **Web-standard APIs only in core** — no `node:*`, no Workers globals above the host
   packages.
4. **The version check is the guarantee; the actor is the optimization.**
5. **`applyPlan` is one transaction**, everywhere, always.
6. **Inject the clock.** `Date.now()` appears in exactly one place per host.
7. **No new port without two implementations.** A seam with one implementation is a
   liability, not an abstraction.

---

## 10. What this costs you

The Node host is ~200 lines (map, mutex, sockets, sweeper). The Cloudflare host is
~150 (DO, alarm, hibernation, Hyperdrive binding). The auth is ~400. The genuinely
expensive part is the one you no longer get for free: **the read API** — lobby,
history, leaderboards, search, friends, replay — which PostgREST used to generate and
which is now yours to write, document, version, and generate a Dart client from. Budget
that honestly; it is the bulk of the work and it produces no new capability, only
independence.

In exchange: the engine runs anywhere Postgres and a fetch handler run, self-hosts in
one `docker compose up`, deploys to Cloudflare in one `wrangler deploy`, and depends on
no vendor for identity, realtime, or data access.

---

## 11. The alternative we did not take — Cloudflare-only

Worth recording honestly, because it is a stronger option than it first appears, and
the case against it is narrower than "lock-in is bad."

### What dual-host actually costs: the *best* Cloudflare design

The real cost of blessing Node is not the ~200 lines of `host-node`. It is that two
simplifications, available only to a Cloudflare-only engine, are permanently
foreclosed:

1. **The DO becomes the HTTP entry point.** Route straight to it with
   `idFromName(gameId)` and let the DO's own `fetch` handler *be* the route handler. The
   command boundary evaporates — an HTTP request already **is** a serializable command —
   and with it goes the Worker→DO hop, the `commandId` dedupe table, and the internal
   wire-format version policy (all of §4.3).
2. **DO SQLite becomes a write-through hot cache** for the current game state, killing
   the `loadGame` round trip to Postgres on every action. Dual-host must forbid this,
   because it would give the two hosts different persistence semantics (§2).

So the comparison is not "the same design with one fewer host." They are two designs.

| | **Dual-host (Node + DO)** | **Cloudflare-only** |
| --- | --- | --- |
| Session entry | Worker mints a `Command` → DO RPC | request routed straight to the DO; the DO *is* the handler |
| Hot state | Postgres on every action, both hosts | DO SQLite write-through cache |
| Idempotency | `commandId` dedupe required (network hop) | not required (no hop) |
| Deadlines | DO alarm **+** a Node boot/interval sweeper | DO alarm only |
| CI | scenario suite runs twice | runs once |
| Design ceiling | the **intersection** of Node and CF limits | CF's limits (which bind anyway) |
| Self-host in prod | **yes** | **no** (local dev works under miniflare; production does not) |
| Vendors | Postgres anywhere + optional CF | Hyperdrive→Neon **plus** CF — still two |

### Two things that table makes obvious

**The intersection tax is smaller than it looks.** Cloudflare's limits bind in nearly
every dimension — 128 MB memory, per-request CPU caps, no background work outside a
request. You design to those ceilings whether or not Node is a target, so "designing to
the intersection" is mostly just "designing for Cloudflare." The genuine extra costs are
narrow and enumerable: the deadline sweeper, sticky routing if Node ever scales past one
process, a `Bus` port to paper over `ws` vs `WebSocketPair`, doubled CI, and the
idempotency machinery in §4.3.

**Cloudflare-only does not get you to one vendor.** D1's 10 GB ceiling does not fit the
storage curve (see `cloudflare_migration_analysis.md` §3e), so the system of record is
Neon or equivalent regardless. The "one platform, one bill" argument for CF-only is
largely illusory.

### Why we bless Node anyway

Not for portability aesthetics — for the **whitelabel premise**. The engine exists so
that *other people deploy it*. A studio with an AWS footprint, a customer with EU
data-residency requirements, or a contributor who wants to run it on a box will all
bounce off a backend that provably cannot run outside Cloudflare. CF-only quietly
converts "an open-source game engine" into "an open-source Cloudflare template," and no
licence fixes that, because **a fork cannot run it**.

### The third option, if the dual-host tax bites

Ship **Cloudflare first and only**, but hold the four disciplines that keep Node
possible: pure kernel, platform-free session, serializable commands, and Postgres — not
DO SQLite — as the system of record. Adding `host-node` later is roughly a week *if* the
discipline held, and unbounded if it did not. One host to maintain now; a credible
self-host story the day someone actually asks.

### The one path to avoid

Claiming both hosts while exercising only one in CI. The failure mode of dual-host is
never the code — it is that the unexercised host silently rots for six months and then
does not work when a stranger tries it, which damages the project more than never having
promised it. **If both are blessed, the scenario suite runs against both on every PR, or
you are Cloudflare-only with extra steps.**
