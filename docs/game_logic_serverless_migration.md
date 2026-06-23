# Game Logic on Serverless — Architecture Decision & Migration Plan

> Status: **decided — final plan below (§10).** Authored 2026-06-23.

## 1. Goal & motivation

Today every game's rules live in **PL/pgSQL hooks** called inside the database
transaction. Writing complex rules (Poker betting rounds, side pots, hand
ranking; multi-player elimination) in SQL is painful, hard to test, and
library-poor. We want to **move game rules into TypeScript** while keeping the
engine's correctness guarantees (atomic, serialized, hidden-info-safe).

Target scale (stated): **~5,000 games/day, peak ~1,000 simultaneous**
(~125 actions/sec peak). Games of interest: Stratego, Poker, etc. — turn-based,
human-paced, latency-tolerant.

## 2. Options considered

| # | Option | Verdict |
|---|--------|---------|
| 1 | Keep rules in SQL hooks (status quo) | Rejected — the SQL pain is the whole problem. Fine for trivial games only. |
| 2a | Pure TS functions called **synchronously from inside SQL** (under the row lock) | **Rejected.** Anti-pattern: blocks a DB backend on an external HTTP call while holding `FOR UPDATE`. Also **impossible on Supabase** — managed Postgres offers only `pg_net` (async); there is no synchronous HTTP-from-Postgres. |
| 2b | Serverless (Cloudflare/Vercel) as the **orchestrator** (client → fn → gated commit RPC) | Viable. Same shape as the chosen path but on a third-party platform. |
| 3 | Persistent stateful game server (VM/container) | Deferred — best high-scale ceiling (own WebSocket, in-memory state), but premature at this scale; more ops. |
| ★ | **Full Supabase — Edge Functions for everything** | **Chosen.** One vendor; co-located with the DB; DB-triggered jobs stay in-network; smallest security surface; one CI/CD toolchain. |

### Why not Cloudflare (the runner-up)

CF Workers/Durable Objects are excellent and slightly cheaper, and DO offers a
unique managed path to a stateful per-game server with its own WebSocket
(which would remove Realtime message costs at high scale). But that only matters
at a scale we are nowhere near, and it adds a second platform, a second deploy
path, and puts a powerful Supabase key in a third-party secret store. Full
Supabase wins on simplicity for where we are. **The decision is reversible**: the
rules module is pure TS, so a future move to CF Workers/DO is a transport-layer
swap, not a rules rewrite.

## 3. Key technical findings

- **Compute is not the bottleneck.** Resolving a Stratego move or a Poker hand is
  sub-millisecond. At this scale the cost/scaling drivers are the same in every
  option: **DB write throughput, Realtime fan-out (messages), DB storage.**
  Where rules *run* is a developer-experience decision, not a scaling one.
- **The lock is RPC-internal.** In the chosen model the `FOR UPDATE` lock lives
  entirely inside one commit RPC (`BEGIN → lock → validate → write → COMMIT`,
  server-side). Distance from EF to DB adds to *per-action latency* (irrelevant
  for turn-based) but does **not** extend lock-hold, so it does not cap
  throughput.
- **Supabase can't synchronously call out over HTTP.** Only `pg_net` (async,
  fire-and-forget) is available. Therefore TS rules **require relocating the
  orchestration** that calls them out of the transaction and into the EF.
  Postgres remains the place where the lock/version/timing/persistence happen,
  invoked *by* the EF — never the other way around.
- **The pattern is already in the codebase (on ratings).** `update-ratings` is
  TS/OpenSkill compute in an EF, woken by a `pg_net` webhook on rated-game finish
  (`net.http_post` → `serverless_base_url/update-ratings`, auth via
  `x-webhook-secret`=`SERVERLESS_SECRET`), writing back through the secret-gated
  `apply_rating_updates` RPC. The game-logic move **generalizes this proven
  pattern**.

## 4. Chosen architecture (target end-state)

Game rules become a **pure TS module** (the six hooks). Supabase Edge Functions
host the orchestration; Postgres keeps lock/version/timing/persistence behind
**secret-gated RPCs**; **Supabase Realtime is unchanged** (clients still
subscribe to their `observations` row).

Two EF invocation patterns — both already used here for ratings/notifications:

- **Synchronous (client-initiated):** action submit, start, forfeit, replay.
  Client calls the EF; the EF reads ground-truth state, runs the TS rules, calls
  the gated commit RPC, returns. (Replaces the client's direct `submit_action` /
  `start_game` / `forfeit_game` / `get_replay` RPC calls.)
- **Async (DB/cron-initiated via `pg_net`):** timeouts (`pg_cron` detects expiry
  → `pg_net` wakes the EF → EF computes the timeout consequence → gated commit
  RPC), plus the existing ratings/FCM webhooks.

### Division of responsibility

| Concern | Lives in |
|--------|----------|
| Game rules (the hooks) | **TS module** (app-owned), run in the EF |
| Orchestration (read → compute → commit) | **EF** (engine-owned harness) |
| Lock, optimistic version check, deadline + grace, bank deduction, observation fan-out, outcome→`game_outcomes`, status flip, append `game_states`/`actions` | **SQL** — a secret-gated commit/persist RPC (the existing `private.commit_action` + the infra half of `private.apply_seat_action`) |
| Timeout detection/scheduling | **SQL** — `pg_cron` + a sweep that `pg_net`-wakes the EF |
| Realtime delivery | **Supabase Realtime** on `observations` (unchanged) |

### Security boundary (critical)

The commit/persist RPC and the timeout endpoint must be callable **only by the
EF** (service-secret / HMAC), never by clients — clients submit *intents*, the
trusted EF submits *computed states*. This mirrors the existing
`submit_bot_action_signed` HMAC gate and the `apply_rating_updates`
`x-webhook-secret` gate. Prefer **narrowly-scoped gated RPCs** over handing the
EF a blanket service-role write capability.

## 5. The hooks and where they're called (why this is non-trivial)

Six hooks (3 core + 3 optional), defined in the **app** repo, called from **~8
sites** across the engine's SQL:

| Hook | Called from |
|------|-------------|
| `game_initial_state` | `start_game_core` |
| `game_apply_action` | `apply_seat_action` (submit + both bot paths) |
| `game_compute_observation` | `update_all_observations`, `start_game_core`, `get_replay` |
| `game_handle_system_action` | `expire_turn` (timeout), `do_forfeit_game` (forfeit) |
| `game_rating_pool` | `derive_rated` (← `create_game`, `preview_game_rating`) |
| `game_bot_seatable` | `seat_server_bot`, `create_solo_game`, `seatable_bot_ids` |

The hooks are **woven throughout** the SQL infra. Moving them to TS means
relocating each *orchestration* that calls a heavy hook to the EF.

## 6. Current SQL vs Edge Function split

**Today:**

- **SQL (PL/pgSQL):** *everything* — all infra orchestration (create/join/leave/
  start/cancel/forfeit/submit/expire/replay/discovery/social/account), the six
  game hooks (app-defined SQL), timing, optimistic locking, deadline grace, bank
  deduction, observation fan-out, outcomes, plus `pg_cron` jobs and the `pg_net`
  triggers that wake EFs.
- **Edge Functions (Deno/TS):** only two peripheral jobs that need JS libraries —
  `update-ratings` (OpenSkill) and `refresh-fcm-token` (Firebase). Both are woken
  by `pg_net` and write back via gated RPCs.

So the existing split is: **SQL = all game + infra logic; EF = the two things SQL
can't do well (rating math, FCM).**

**Proposed split (natural seam):**

- **→ TS / EF (heavy, stateful rules):** `game_initial_state`,
  `game_apply_action`, `game_handle_system_action`, `game_compute_observation`.
  Their orchestrations (start, submit, forfeit, timeout, fan-out, replay) move to
  the EF + gated commit RPCs.
- **→ stay SQL (light predicates in SQL-only flows):** `game_rating_pool`,
  `game_bot_seatable`. These are simple predicates called from pure-SQL paths
  (`create_game`, seating, preview). They are trivial to write in SQL and moving
  them to TS would force `create_game`/seating through an EF for no benefit.

## 7. Configurability — can it / should it?

**Can it?** Yes, technically — the hook seam is a clean pure-function boundary.
But on Supabase, *heavy* hooks in TS force EF orchestration (no sync HTTP from
PG), which also changes the **client transport** (client → EF instead of client →
`submit_action` RPC). So configurability is not free.

Two meaningfully different notions:

- **(I) Single model.** Everyone uses EF/TS for the four heavy hooks; the two
  predicate hooks stay SQL. One orchestration path, one client transport.
  Simplest engine. Even a trivial game runs through the EF (but it had to deploy
  the EF anyway, since each app ships one game).
- **(II) Per-app configurable.** The engine keeps **both** the legacy all-SQL
  in-transaction path *and* the EF/TS path; each whitelabel app picks. Simple
  games keep the atomic, lowest-latency SQL model; complex games get TS. Cost:
  the engine maintains **two orchestration paths + two client transports + tests
  for both, indefinitely** — a permanent split-brain in the engine core.

**Recommendation:** lean **(I)**. The per-hook-language flexibility of (II) buys
little (you pay for the EF regardless), while doubling the engine's most
critical, hardest-to-test surface. Keep configurability at the *cheap* layer
(the predicate hooks stay SQL; the rules module is pure TS and portable) rather
than at the *expensive* layer (dual orchestration). **Open for decision — see
§9.**

## 8. Cost at target scale (~5k games/day, peak ~1k)

Compute is a rounding error; Supabase platform dominates. Indicative monthly:

| Line | ~Cost |
|------|------|
| Supabase Pro | $25 |
| Compute add-on (Small/Medium) | $0–50 |
| Realtime connections (~3k peak) | ~$25 |
| Realtime messages (scales with actions×players) | ~$33–100 |
| Edge Functions (~6M invocations: 2M incl., then ~$2/M) | ~$8 |
| Storage (append-only history) | low |
| **Total** | **~$95–230/mo** |

Free-tier note: EF free = 500k/mo (pooled); at target you're on Pro anyway.

## 9. Decisions (resolved 2026-06-23)

1. **Configurability:** **Single EF/TS model.** No dual orchestration; predicate
   hooks stay SQL, everything else is one path.
2. **Hook split:** **Four heavy → TS, two predicates → SQL.**
3. **Delivery:** **Vendored, mirror migrations** — the engine EF harness is
   synced into each app via the existing Dart CLI ([[supabase-migration-sync-approach]]).
4. **Scope:** **Big-bang, including bots** (server-bot HMAC path, local-bot
   client path) and the system-action paths reachable from account deletion /
   stale-guest cleanup.

## 10. Final plan

### 10.0 Shape in one paragraph

The four heavy hooks become a **pure TS rules module**. A single **engine-owned
Edge Function** (vendored into each app) orchestrates every flow that used to
call a heavy hook: it reads ground-truth state via a **gated read RPC**, runs the
TS rules, computes each seat's observation slice, and calls a **gated commit
RPC** that takes the `FOR UPDATE` lock and owns version/deadline/bank/persistence/
fan-out. Postgres keeps every correctness guarantee under the lock; only the
*rules* and the *observation projection* move to TS. Realtime, the two predicate
hooks, and all non-hook SQL infra are unchanged. Timeouts and account-deletion
forfeits reach the EF via `pg_net`, exactly like the existing rating webhook.

### 10.1 Entry-point map (current → target)

| Current | Heavy hook? | Target |
|--------|-------------|--------|
| `create_game`, `preview_game_rating` | predicate only | **Unchanged SQL** (`game_rating_pool` stays SQL) |
| `join_game`, `join_game_by_code`, `leave_game`, `cancel_game` | no | **Unchanged SQL** |
| `seat_server_bot`, `add_bot_to_game`, `seatable_bot_ids`, `get_bots` | predicate only | **Unchanged SQL** (`game_bot_seatable` stays SQL) |
| `get_local_bot_observation` | no (reads stored row) | **Unchanged SQL** |
| `get_lobby_games`, `get_friends_games`, `get_players`, social, account-read | no | **Unchanged SQL** |
| `start_game` / `start_game_core` | `game_initial_state`, `game_compute_observation` | **EF `start`** → gated `engine_commit_start` |
| `submit_action` | `game_apply_action` (+ obs fan-out) | **EF `action`** → gated `engine_commit_action` |
| `forfeit_game` / `do_forfeit_game` | `game_handle_system_action` | **EF `forfeit`** → gated `engine_commit_action` (system) |
| `trigger_turn_expiry`, `expire_all_turns`/`expire_turn` | `game_handle_system_action` | **EF `expire`** (client nudge + `pg_cron` sweep via `pg_net`) |
| `get_replay` | `game_compute_observation` ×N | **EF `replay`** (gated read + TS projection, no commit) |
| `submit_bot_action_signed` | `game_apply_action` | **EF `bot-action`** (HMAC verified via gated RPC) → commit |
| `submit_local_bot_action` | `game_apply_action` | **EF `local-bot-action`** → commit |
| `create_solo_game` (start portion) | `game_initial_state`, … | SQL create+seat unchanged; **start portion → EF `start`** |
| `delete_account`, `cleanup_stale_anonymous_users` (forfeit portion) | `game_handle_system_action` | active-game forfeits **→ EF**; pure-SQL purge (cancel/leave/delete) retained |

### 10.2 Workstreams (dependency order)

**A. Contracts & types (engine, TS).**
- Define the four TS hook signatures + envelope types, mirroring the SQL hook
  contracts in the implementation guide. Pure interface, no Supabase imports.
- Provide a **default passthrough** `game_compute_observation` (mirrors today's
  SQL default for perfect-info games).
- Define the EF↔RPC payload types (read result, commit request incl. the
  per-seat observation array).

**B. SQL — gated read RPCs (engine migration).** Service-secret gated (revoke
from `anon`/`authenticated`; callable only by the EF). Each takes the EF-verified
`caller_id` where authorization is needed.
- `engine_read_game_state(game_id)` → games meta (config, timing, schema_version,
  status) + latest `game_states` (state, pending, version, seed, deadline,
  player_times, turn_started_at) + the participant roster (seat→user/bot).
- `engine_read_for_start(game_id)` → config, player_count, schema_version, timing,
  status (must be `ready`).
- `engine_read_states_for_replay(game_id, caller_id)` → all `game_states` +
  `actions`, after gating (finished + caller is participant).
- `engine_verify_bot_hmac(bot_id, payload, signature)` → bool (reuses
  `verify_bot_action_hmac`; keeps the Vault secret in the DB).

**C. SQL — gated commit RPCs (engine migration).** Refactor the *infra half* of
`apply_seat_action` / `start_game_core` out from the hook calls; reuse
`private.commit_action`, `private.finish_game`, `private.compute_next_deadline`.
- `engine_commit_action(game_id, mode, caller_id, acting_bot_id, player_index,
  action_data, expected_version, new_state, new_pending, new_seed, outcome,
  turn_seconds, observations[])` where `mode ∈ {user, bot, system_forfeit,
  system_timeout}`. Under the games `FOR UPDATE` lock it: re-reads latest state;
  re-checks status + deadline(+grace); for `user`/`bot` validates version and
  `player_index ∈ pending`; for `system_timeout` re-checks expiry(+grace) and
  abstains if a real action won; applies bank deduction (infra, `NOW()` at lock);
  appends `game_states` + `actions`; `finish_game` if outcome; **writes the
  EF-provided observation slices, stamping version + timing infra-side**.
- `engine_commit_start(game_id, initial_state, pending, seed, turn_seconds,
  observations[])` → writes `game_states` v0 + per-seat observations + timing,
  flips status to `active`. Idempotent (no-op if already `active`).
- **Observation fan-out split:** TS computes each seat's `data`/`pending_players`;
  SQL stamps `version`/`turn_deadline`/`player_times`/`turn_started_at` and
  writes. `private.update_all_observations` is replaced by this
  write-provided-slices form (it no longer calls the hook).

**D. SQL — timeouts & system paths (engine migration).**
- Replace `expire_all_turns` with `engine_expire_sweep()`: same expired-deadline
  query, but `pg_net` POST `{game_id}` + secret to EF `expire` per game. Keep the
  per-minute `pg_cron` schedule.
- Split `purge_user`: keep the pure-SQL `engine_purge_user(user_id)` (cancel/leave
  waiting games, delete `auth.users`); the **active-game forfeits move to the EF**
  (`delete-account` and a `pg_net`-woken `cleanup-stale-guests`). Make the
  sequence resumable (forfeit all active → then purge).

**E. SQL — decommission heavy-hook call sites & client RPCs (engine migration).**
- Drop the SQL expectation of `game_apply_action` / `game_initial_state` /
  `game_compute_observation` / `game_handle_system_action`. Keep
  `game_rating_pool` + `game_bot_seatable`.
- Remove (or replace with an erroring shim) the now-relocated public RPCs:
  `submit_action`, `start_game`, `forfeit_game`, `trigger_turn_expiry`,
  `get_replay`, `submit_bot_action_signed`, `submit_local_bot_action`. Coordinate
  with the client release via `schema_version` so no build calls a removed RPC.

**F. Edge Function harness (engine, vendored into app).** One function with
internal routing (one deploy, one cold-start surface). Endpoints: `action`,
`start`, `forfeit`, `expire`, `replay`, `bot-action`, `local-bot-action`,
`delete-account`, `cleanup-stale-guests`. Shared pipeline:
1. Authenticate — human JWT (verify → `caller_id`), or HMAC (bot via
   `engine_verify_bot_hmac`), or `x-webhook-secret` (cron/`pg_net` paths).
2. `engine_read_game_state` (service role).
3. Invoke the **app rules module** (apply / initial_state / handle_system_action).
4. Compute observations for every seat via the TS `game_compute_observation`.
5. `engine_commit_*` (service role) with precomputed result + observation array.
6. Map errors (stale version → existing humanized client message).
- Config: reuse `private.app_config.serverless_base_url`, the `SERVERLESS_SECRET`
  / `x-webhook-secret` convention, and `SUPABASE_SERVICE_ROLE_KEY` (as
  `update-ratings` already does).

**G. App rules module (the seam, per app).** Pure TS implementing the four heavy
hooks against the engine types. Port the app's existing SQL heavy hooks → TS.
Keep the old SQL hooks in version control until the TS port is trusted (rollback).

**H. Client (Dart, per app).** Replace the relocated `rpc(...)` calls with
`functions.invoke(...)` to the EF endpoints (`action`/`start`/`forfeit`/`replay`/
`expire`/`local-bot-action`). Realtime subscription on `observations` unchanged.
Reuse existing error mapping.

**I. Bots.** Server bots: change the callback target from the
`submit_bot_action_signed` RPC to the EF `bot-action` URL (the wake trigger,
HMAC, and Vault secret are unchanged — the wake still fires on the observation
write done inside the commit RPC). Local bots: client → EF `local-bot-action`;
`get_local_bot_observation` stays SQL.

**J. Tooling / CI / dev (engine).**
- Extend `bin/sync_supabase.dart` to also vendor the EF harness into the app
  (same model as migrations).
- Scaffold: a starter rules module + `config.toml` function entry + secrets list.
- Local dev: one script — `supabase start` + `supabase functions serve` +
  `flutter run`, env wired.
- CI: `supabase functions deploy` + `db push`, ordered; gated by `schema_version`.
- Golden tests for the TS rules module (incl. **rng_seed determinism** — BigInt
  xorshift must match the SQL `prng_next` results for any pre-migration replays).

### 10.3 Cutover & rollback

- **Big-bang but co-released:** ship SQL migration + EF + client together; the
  `schema_version` gate prevents an old client from acting against new infra.
- **No data migration** — `game_states`/`observations` shapes are unchanged;
  state JSON is language-agnostic, so existing finished games still replay (the
  TS observation hook must reproduce the SQL projection — covered by golden tests).
- **Rollback:** revert the engine migration (re-adds the old RPCs + SQL
  hook call sites) and redeploy the old client. Keep the app's SQL hooks in VCS
  until the TS port is proven.

### 10.4 Idiomatic architecture — keep vs rethink (not a blind port)

The SQL design made some choices that are *right for any stack* and others that
were *SQL artifacts*. This migration keeps the former for stack reasons (stated)
and redesigns the latter.

**Keep — and why it's idiomatic here, not merely inherited:**

- **One atomic commit RPC** writes state + all observation slices + action +
  outcome under a single lock. Required by Realtime: a subscriber must never see
  an observation whose `version` is inconsistent with the committed state.
- **Lock only inside the commit RPC (optimistic CAS).** EF reads unlocked,
  computes, then one RPC does `lock → re-validate → write`. Holding the lock
  across the EF (pessimistic) is strictly worse for lock-hold and session mgmt.
- **Eager, materialized observation fan-out.** Realtime can only push *stored
  rows* under RLS — it cannot run per-subscriber projections — so eager fan-out
  is what makes hidden-info + Realtime coexist. Not legacy; mandatory.
- **Timing/bank math stays in SQL at lock-time.** Bank deduction needs `NOW()` at
  lock acquisition; the EF computes rules before the lock. Split: **EF owns the
  view *data*; SQL stamps the timing *columns*** on state + observation rows. The
  EF supplies only the optional `turn_seconds` hook override.

**Rethink — exploit what the EF stack enables:**

1. **Rules as one typed `GameRules` interface**, not six global functions
   (`initialState`, `applyAction`, `handleSystemAction`, `computeObservation`
   sharing typed state + helpers). The "six discrete functions" was a SQL seam.
2. **`applyAction` returns a `Result`**, not exception-as-control-flow:
   distinguish **illegal move** (→400), **stale version** (→409, "board
   changed"), **internal error** (→500).
3. **`expected_version` is authoritative — preserve "you act on what you saw."**
   The EF computes from exactly the client's claimed version and rejects as stale
   *without computing* if the DB is already ahead; the commit re-checks under
   lock. Easy to lose in relocation; keep it explicit.
4. **Idempotency is now first-class** (EF endpoints get retried / `pg_net`
   redelivered). Existing guards already provide it — version CAS (actions),
   deadline re-check (timeout), no-op-if-active (`start`) — but design and
   document to it per endpoint rather than rediscover it.
5. **`computeObservation` stays a distinct, reused pure function** (used by apply,
   `start`, `replay` with `isReplay`); only the fan-out *orchestration* moves to
   the EF. Optional: a **batch** `computeObservations(state) → Map<seat, slice>`
   so games compute shared public data once (nice for Poker); default per-seat.
6. **Keep finish → rating/notification as DB triggers — do not inline** into the
   EF. A trigger on finish is a single point covering *all* finish paths (action,
   forfeit, timeout); inlining forces every commit path to remember it.
7. **Batch multi-step system commits.** The `expire_turn` per-pending-player loop
   resolves in-memory in the EF and hands the commit RPC an **ordered array of
   transitions** written atomically under one lock — preserves per-step replay
   history in one round trip. Generalizes commit to "apply these K transitions."
8. **Consolidated read + explicit rules↔schema coupling.** One read RPC/view
   returns games-meta + latest state + roster in a single round trip; the EF
   asserts its rules version is compatible with `schema_version` at the boundary.

**Considered & rejected:** EF-runs-the-whole-transaction (lock across network);
lazy on-read observations (breaks Realtime push); CQRS/async projection (breaks
synchronous move results); orchestration-in-SQL-calling-EF (no sync HTTP from PG).

### 10.5 Risks / watch-items

- **Atomicity loss** on `create_solo_game` (create+seat then EF-start) and
  `delete_account` (EF-forfeit then purge) → idempotent/resumable `commit_start`
  and purge.
- **TOCTOU** between EF read and commit → handled by the version check under lock
  (same optimistic semantics as today; surface conflicts to the client).
- **Determinism** of the TS PRNG vs SQL `prng_next` for replay parity → golden
  tests.
- **Security:** commit/read RPCs are service-secret only; `bot-action` is
  HMAC-only; never expose to `authenticated`/`anon`. Prefer scoped gated RPCs over
  blanket service-role table writes.
- **Latency:** per action = 2 PG round trips from the co-located EF (read +
  commit) — negligible for turn-based at this scale.
