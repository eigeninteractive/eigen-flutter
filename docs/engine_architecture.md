# Eigen Engine — System Design

> **Architecture at a glance.** The game's **rules are TypeScript** — a
> `GameModule` registering one **`GameRules` unit per `schema_version`** (six
> hooks + Zod schemas each, §4) that the engine's **edge function** resolves
> and invokes at its commit chokepoint; the client carries a Dart `GameModule`
> (a same-keyed registry of client `GameRules` units — rendering, action
> validation, local twins of `ratingPool`/`botSeatable`) but never decides
> rules. There is **one `engine` edge function** with four auth-tiered route
> groups (`game`, `social`, `internal`, `bot`, §21). Every state-changing
> operation goes through an edge-function route that runs the rules and commits
> through a **gated, service-role `engine_*` SQL RPC** — a thin atomic writer
> that keeps only the lock/transaction work, with policy (validation, guest
> gating from the JWT, the rating decision) in TypeScript and integrity
> backstopped by `games` CHECK/`UNIQUE`/FK constraints (§5). Ratings (OpenSkill)
> are computed in the EF and written **in the finishing transaction** (§8); FCM
> pushes are emitted by the EF post-commit and from the `social` routes (§20);
> server-bot auth is a derived `HMAC(BOT_SIGNING_SECRET, bot_id)` (§26); game
> randomness is a deterministic per-transition RNG (`rand-seed`, derived in
> `_engine/observation.ts`). A residual tier of **client-direct** RPCs (lobby
> joins, discovery, search — §5) the Dart client still calls over PostgREST
> under RLS.

## 1. Vision & Architecture

The goal is to build a **reusable "whitelabel" game engine**. Each app instance
runs exactly **one** game (e.g., "Strategy Chess", "Strategy Poker"), but the
underlying `core` codebase is identical.

### Architectural Separation

- **Core Engine (The "Framework")**: Auth, user management, game networking,
  rating system, settings. Owns the `users`, `games`, `game_states`,
  `observations`, `participants`, `actions`, and `game_outcomes` tables, the
  gated SQL RPCs, and the **edge function** that orchestrates every game
  transition.
- **Game Module (The "Implementation")**: The specific rules, board rendering,
  and action validation for this specific app. It supplies the rules as a
  **TypeScript `GameModule`** — a registry of **`GameRules` units keyed by
  `schema_version`**, each bundling six hooks (`initialState`, `applyAction`,
  `computeObservation`, plus optional `ratingPool`, `applyLifecycle`,
  `botSeatable`) and the **Zod schemas** the edge function parses every payload
  through before a hook runs — and a **Dart `GameModule`** for the client (a
  same-keyed registry of client `GameRules` units: rendering, action
  validation, and local twins of `ratingPool` / `botSeatable`). The framework
  owns version dispatch — each game row resolves its own unit, so game code
  never branches on version. The pure game logic is platform-shared TypeScript
  run on the server; the client never decides rules.

### Design target — game variety

The contract above is deliberately shaped to span a wide range of turn-based
games, each stressing a different generality dimension:

- **Chess** — classic single-piece-move board game (the baseline).
- **Dama** — actions with **multiple steps** (a chained capture is one action).
- **Hive** — **boardless**, hexagonal-grid placement with no fixed coordinates.
- **Literature (Canadian Fish)** — **hidden-information** team play (see §6).
- **Poker** / **dice-roll games** — **chance** and hidden state per player.
- **Set** — simultaneous pattern-spotting over a shared tableau.
- **RPS** — **simultaneous** moves rather than strictly alternating turns.
- **Exploding Kittens** — deck/hand state with reactive, event-driven effects.

These are design inputs, not a roadmap: the opaque-JSONB state, the
`computeObservation` per-seat hidden-information slice, and the
`applyAction`/`applyLifecycle` split exist so games this varied can plug in without
changing the framework.

---

## 2. Database Design

### Tables

#### `users` (System/Immutable)

- `id` (uuid, PK, references auth.users)
- `username` (text, unique) — for guests, a generated `player_NNNNN` handle
- `email` (text, unique, **nullable**) — null for anonymous (guest) users until
  they convert to a permanent account; backfilled by the conversion trigger
- `payment_tier` (text, default 'free')
- `created_at`, `updated_at`

The `handle_new_user` trigger provisions this row on signup: from the email
prefix for a normal signup, or a generated `player_NNNNN` handle when the new
`auth.users` row has no email (an anonymous guest). See §25 for the guest-auth
lifecycle.

#### `user_profiles` (User Editable)

- `id` (uuid, PK, fk to users)
- `display_name` (text)
- `avatar_url` (text)
- `updated_at`

#### `games` (Game Metadata)

- `id` (uuid, PK)
- `created_by` (uuid, nullable fk to users, **ON DELETE SET NULL**) — the host;
  SET NULL when the account is deleted (the game row is preserved)
- `status` (enum: `waiting`, `ready`, `active`, `finished`, `aborted`)
- `access` (enum: `public`, `private`, `friends`)
- `turn_seconds` (int, nullable) — per-action timer mode: each turn gets a fresh
  N seconds. Null means no per-action timer. **Mutually exclusive with
  `budget_seconds`.**
- `budget_seconds` (int, nullable) — accumulated clock mode: each player has a
  personal time bank of N seconds that drains while they are acting. Null means
  no bank. **Mutually exclusive with `turn_seconds`.** See §3 for the
  sequential-only constraint.
- `increment_seconds` (int, nullable) — Fischer increment: seconds added to the
  acting player's bank after each bank-consuming action. Only valid when
  `budget_seconds IS NOT NULL`. Null treated as 0.
- `min_players` (int, default 2) — minimum participants required to transition
  the game to `ready` status. The host can start once this threshold is met.
- `max_players` (int, default 2) — maximum participants allowed to join.
  `app_join_game` rejects once this is reached.
- `config` (jsonb) — game-specific configuration passed through to the three
  game hooks. Infra never reads this.
- `rated` (boolean, default false) — true if this game affects player ratings.
  The client sends a concrete `rated` assertion; the `game/create` route
  recomputes eligibility (`ratingPool` non-null and a non-guest caller) and
  **validates** it, rejecting a mismatch rather than coercing. See §5, §8.
- `rating_pool` (text, nullable) — the pool this game's results will be counted
  in (e.g. `'rapid'`, `'daily'`). Always `NULL` when `rated = false`. Derived by
  the `ratingPool` hook server-side; clients cannot forge it.
- `short_code` (varchar(6), unique, not null) — human-readable join code
  generated at game creation. Used by `app_join_game_by_code` for invite-by-code
  joining. Generated via `upper(substring(md5(random()::text) from 1 for 6))`
  with a retry loop on unique violations. Always set — `engine_create_game`
  loops until a unique code is found.
- `created_at`, `finished_at`, `updated_at`
- **Constraints**: `turn_seconds IS NULL OR budget_seconds IS NULL` (timing mode
  exclusive); `increment_seconds IS NULL OR budget_seconds IS NOT NULL`
  (increment requires budget);
  `min_players >= 1 AND max_players >= min_players`;
  `NOT rated OR rating_pool IS NOT NULL` (if rated, pool must be set).

#### `game_outcomes` (Per-Player Results — Service Role Only Writes)

- `game_id` (uuid, fk to games, PK composite)
- `player_index` (int, PK composite) — 0-based player slot
- `user_id` (uuid, nullable fk to users, **ON DELETE SET NULL**) — null for
  bots; SET NULL when the account is deleted so the outcome row is preserved for
  analytics and replay attribution
- `bot_id` (uuid, nullable fk to bots) — null for humans
- `result` (text, CHECK: `win`, `loss`, `draw`, `eliminated`)
- `score` (numeric, nullable) — raw game score; optional, for display or future
  score-based variants
- `placement` (int, NOT NULL) — ordinal finish rank (1 = best); ties share the
  same value. Passed directly to OpenSkill as the rank input. See §8.
- `team_index` (int, NOT NULL) — groups players into rating teams. Players
  sharing a value are rated together. Use `player_index` for individual games
  (each player is their own team of one); teammates share a value for team games
  (e.g. Literature, Canadian Fish). See §8.
- **Identity constraint**: `NOT (user_id IS NOT NULL AND bot_id IS NOT NULL)` —
  at most one identity is set. Both may be NULL when the human player's account
  was deleted after the game finished. `player_index` is always preserved and is
  the authoritative attribution key.

A scalar winner column can't express team wins (Literature), multiple placements
(Poker), or mid-game eliminations. One row per participant handles all of these.

#### `game_states` (Append-Only State History — Service Role Only)

One row is INSERTed per state transition; rows are never UPDATEd. Current state
= `ORDER BY version DESC LIMIT 1`. The full history enables zero-compute replay
via the `game/replay` route — no action log re-execution needed.

- `game_id` (uuid, fk to games, composite PK with `version`)
- `version` (int, composite PK) — monotonically incrementing counter starting at
  0 (initial state). Used for optimistic locking. Mirrored to every
  `observations` row.
- `state` (jsonb) — pure game payload: board, deck, fog map, etc. Does **not**
  carry whose-turn or winner info — those are first-class infra columns.
- `pending_players` (int[]) — 0-based indices allowed to act now. Singleton for
  sequential games; full set for any-player games; empty when no one may act
  (game over / paused). Stored here (not only in observations) so replay can
  call `computeObservation` for each historical row without re-running game
  logic.
- `rng_seed` (text) — the game's base RNG seed: an opaque random string written
  once at start (v0) and copied verbatim onto every later row by the commit RPC.
  The EF derives each transition's generator from `'<rng_seed>:<version>'`
  (`rand-seed` sfc32), so replay re-derives every draw. Never exposed to
  clients — it lives on this service-role-only table (not on the
  participant-readable `games` row) because the game's entire future randomness
  is derivable from it.
- `turn_deadline` (timestamptz, nullable) — absolute deadline for the current
  pending player(s). Set by infra after every action using the timing precedence
  chain (see §3). Null for untimed games. Used by the commit RPC (expiry guard)
  and the `internal/expire` sweep (cron).
- `player_times` (bigint[], nullable) — remaining bank in **milliseconds** per
  player, 1-indexed (`player_times[player_index + 1]`). Null for non-budget
  games. Infra-owned: updated on every bank-consuming action.
- `turn_started_at` (timestamptz, nullable) — timestamp when the current turn
  began, set to transaction time after every action. Used by the commit RPC to
  compute elapsed time for bank deduction. Null for untimed games.
- `created_at` — when this version was committed. Useful for audit and replay
  timeline.
- **RLS**: No policies — service role only.
- **Indexes**: `(game_id, version DESC)` covers current-state lookup and
  `expire_all_turns` DISTINCT ON. Partial index on
  `turn_deadline WHERE NOT NULL` for the cron sweep.

#### `observations` (Player-Specific Projections)

- `game_id`, `player_index`, `version` (**PK composite**) — **append-only
  history**, mirroring `game_states`: one row per participant per state
  version, human **or** bot; rows are immutable once written. Append-only is
  what makes the client's frame stream *reliable*: Realtime can drop INSERT
  events, but a client that sees a version gap fetches the missing rows and
  animates through them in order — and the live stream and a replay become
  the same shape (an ordered per-seat frame sequence). "Current observation"
  = a seat's highest-version row. The table is generalised so bot seats
  receive observations too, which is what lets the turn-notification trigger
  wake a server bot with its view already computed (see §26).
- `user_id` (uuid, nullable fk to users, ON DELETE CASCADE) — set for a human
  seat
- `bot_id` (uuid, nullable fk to bots, ON DELETE CASCADE) — set for a bot seat
- `data` (jsonb) — game-specific state slice computed by `computeObservation`.
  Perfect-info games see the full state; hidden-info games see only their
  permitted slice. May embed per-seat transition cues (e.g. a `lastMove`
  field): the hook receives the transition's `cause` (move / event / null for
  the initial frame) precisely so games can tell each seat what happened —
  the animation channel is the observation itself, never a side channel that
  could leak hidden info.
- `pending_players` (int[]) — this seat's view of the pending set. For
  perfect-info games mirrors `game_states.pending_players`; hidden-info games
  may narrow it (e.g. Exploding Kittens Nope window), but must never drop the
  seat's own membership from its own row — clients derive "is my turn" from it
  (narrowing rules: game_implementation_guide.md, Hook 3).
- `version` (int) — mirror of `game_states.version`. Clients pass this back as
  the optimistic lock key on `game/action`.
- `turn_deadline` (timestamptz, nullable) — mirror of
  `game_states.turn_deadline`. Clients use this to display countdown timers
  without a separate query.
- `player_times` (bigint[], nullable) — mirror of `game_states.player_times`.
  Clients use this to display per-player accumulated clock budgets.
- `turn_started_at` (timestamptz, nullable) — mirror of
  `game_states.turn_started_at`. Combined with `player_times`, clients animate
  the active player's live countdown without polling:
  `remaining = player_times[myIndex] - elapsed_since(turn_started_at)`.
- `created_at`
- **Realtime**: enabled (INSERT events). The game screen subscribes by
  `game_id`; the repository delivers frames **in version order with gaps
  recovered** (a missed version is fetched by range), starting from the
  latest frame on a cold (re)connect. Home screen uses fetch-on-enter +
  pull-to-refresh.
- **Identity constraint**: `(user_id IS NULL) != (bot_id IS NULL)` — exactly one
  identity per row.
- **RLS**: Users see only their own rows (`user_id = auth.uid()`). Bot rows
  (`user_id` NULL) are invisible to clients and Realtime — bots never subscribe;
  a server bot's row is pushed to its webhook and a local bot's latest is read
  by a gated RPC (see §26).

#### `participants`

- `id` (uuid, PK)
- `game_id` (uuid, fk, ON DELETE CASCADE)
- `user_id` (uuid, nullable fk to users, **ON DELETE SET NULL**) — null for bot
  participants; SET NULL when the account is deleted so the seat row is
  preserved for `gamePlayersProvider` and replay participant counts
- `bot_id` (uuid, nullable fk to bots) — null for human participants; both
  `user_id` and `bot_id` can be null simultaneously when the account was
  deleted — mid-game (after the purge's forfeit, when the rules leave the game
  active) or after it finished
- `player_index` (int) — 0-based seat (authoritative seat attribution key)
- `type` (participant_type, default 'human')
- `created_at`
- **Unique**: `(game_id, user_id)` where `user_id IS NOT NULL`;
  `(game_id, player_index)`
- **Identity constraint**: `NOT (user_id IS NOT NULL AND bot_id IS NOT NULL)` —
  at most one identity is set. Both may be NULL after account deletion. The
  `game/delete-account` route explicitly removes the participant row for
  waiting/ready games (cancel/leave inside `engine_purge_user`), so the null
  state occurs on finished games — or on a still-**active** game when the
  purge's forfeit consequence leaves it live (game-defined; a 3+ player game
  may continue). The engine tolerates such a seat: the observation fan-out
  skips it (no viewer, no slice — see `write_observation_slices`) and a rated
  finish emits no rating write for it (`computeRatings` keeps the seat in the
  OpenSkill field but drops its result). Clients render it as "Deleted User".

#### `actions` (Audit Log — Service Role Only)

- `id` (uuid, PK)
- `game_id` (uuid, fk, ON DELETE CASCADE)
- `user_id` (uuid, nullable fk to users, **ON DELETE SET NULL**) — set for human
  actions; null for bot/system actions; SET NULL when account is deleted (the
  action row is preserved for the audit log)
- `bot_id` (uuid, nullable fk to bots) — set for bot actions; null for
  human/system actions
- `type` (enum: `user`, `bot`, `system`)
- `kind` (enum: `game`, `lifecycle`) — the action's **species**, stamped at
  commit. Everything that transitions state is an *action*; a `game` action is
  rules-scoped (game-defined payload, validated by `applyAction`, rejectable),
  a `lifecycle` action is engine-scoped (timeout / forfeit / auto_forfeit,
  resolved unconditionally by `applyLifecycle`). Orthogonal to `type`, which
  records the performer — replay classifies the log by this column, never by
  payload shape.
- **Identity model.** The identity columns (`user_id`, `bot_id`, `player_index`)
  record **who performed the action and from which seat**. A `system` action has
  no performer, so all three are NULL; what it _did_ lives in `data` (the
  `lifecycle_type`) and its _consequences_ in the resulting state / `game_outcomes`.
  A **voluntary resign is a `user` action of kind `lifecycle`** (the user
  performed it); only an **engine-driven forfeit** (account deletion) is a
  `system` action, logged with `data.type = 'auto_forfeit'`.
- **Constraint** `actions_identity_check`: `user` → `bot_id IS NULL` (user_id
  may be null after deletion); `bot` → `bot_id NOT NULL, user_id NULL`; `system`
  → `user_id`, `bot_id`, **and `player_index` all NULL** (no performer).
- `data` (jsonb)
- `player_index` (int, nullable) — **denormalized seat of the performer**,
  written at commit time from the participant row. Survives user deletion; lets
  replay attribute an action to a seat without joining `participants`. Set for
  user moves, bot moves, and a user resign; **NULL for every system action**
  (timeout, engine-driven forfeit), which has no performer.
- `version_after` (int, NOT NULL) — the `game_states.version` produced by this
  action, a **composite FK**
  `(game_id, version_after) → game_states(game_id,
  version)` with a **UNIQUE**
  on the same pair. Every action produces exactly one new state (1:1); the only
  state without an action is the initial state (`engine_commit_start`). The FK
  enforces referential integrity and pins the write order (state row before its
  action); the UNIQUE makes it a _to-one_ so PostgREST embeds the producing
  action under its state for the replay read.
- `created_at`

#### `relationships` (Friends)

- `id` (uuid, PK)
- `user_id_1`, `user_id_2` (fk, canonical order: `user_id_1 < user_id_2`,
  `ON DELETE CASCADE`)
- `initiated_by` (fk to users, `ON DELETE CASCADE`)
- `status` (enum: `pending`, `accepted`, `blocked`)
- `created_at`, `updated_at`
- **Unique**: `(user_id_1, user_id_2)`
- **Indexes**: `user_id_1`, `user_id_2`, `status`
- **RLS**: `SELECT` for authenticated users where
  `auth.uid() IN (user_id_1, user_id_2)`. All mutations go through
  `SECURITY DEFINER` RPCs.
- **Realtime**: enabled.

#### `bots` (Bot Player Registry)

- `id` (uuid, PK)
- `username` (text, unique) — short handle (e.g. `'easy_ai'`), displayed like a
  player username. For a **local** bot this is also the key that selects the
  matching `GameRules.localBots` implementation (on the game's version unit) (`LocalBot.username`).
- `display_name` (text) — human-readable name (e.g. `'Easy AI'`)
- `avatar_url` (text, nullable) — bot avatar
- `schema_version` (int, NOT NULL) — highest game schema this bot supports;
  seating refuses a bot whose `schema_version` is below the game's, mirroring
  the human join gate. No default — the operator states it at insert.
- `is_local` (bool, NOT NULL) — **authoritative locality.** `true` ⇒ driven by
  the sole human's own client (no server transport); `false` ⇒ a server-side bot
  with its own endpoint. Never inferred from the transport columns, so the
  server-bot auth scheme can evolve independently.
- `webhook_url` (text, nullable) — where to wake a server-side bot; NULL for
  local. No key material is stored on the row.
- `rated_eligible` (bool, NOT NULL, default false) — may this bot play rated
  games.
- `config` (jsonb, NOT NULL, default `'{}'`) — per-bot parameters; lets one
  implementation back many separately-rated personas (N:1), and declares which
  game configs the bot supports (read server-side by the `botSeatable` hook; the
  pickers filter client-side via the Dart `botSeatable` twin). **Public
  read-only reference data** — `app_bots` exposes it for both local and server
  bots; never put secrets here. The engine imposes no schema on it.
- `created_at`
- **CHECK** (`bot_transport_consistent`): local ⇒ no `webhook_url`; server ⇒
  `webhook_url` present.
- **RLS**: no direct client SELECT. In-game identity resolves via
  `app_players()`; the pickers use the `app_bots()` RPC (display-safe columns
  only — never `webhook_url`; `config` is exposed). Write/read of the full row
  is service role only.
- **Per-bot HMAC key** (server bots): derived in the edge function as
  `HMAC(BOT_SIGNING_SECRET, bot_id)` — no per-bot secret on this row or in
  Vault. It authenticates both the wake (us→bot) and the action (bot→us). See
  §26.

#### `player_ratings` (Per-Player Per-Pool OpenSkill Rating)

- `id` (uuid, PK)
- `user_id` (uuid, nullable fk to users, ON DELETE CASCADE)
- `bot_id` (uuid, nullable fk to bots, ON DELETE CASCADE)
- `pool` (text) — rating pool name (e.g. `'rapid'`, `'daily'`)
- `mu` (double precision, default 25.0) — OpenSkill mean skill estimate
- `sigma` (double precision, default 25.0 / 3.0) — OpenSkill uncertainty
- `display_rating` (int, default 0) — `max(0, round((mu - 3 × sigma) × 40))`.
  Denormalised for cheap leaderboard queries.
- `created_at`, `updated_at`
- **XOR constraint**: `(user_id IS NULL) != (bot_id IS NULL)`
- **Unique indexes**: `(user_id, pool)` where `user_id IS NOT NULL`;
  `(bot_id, pool)` where `bot_id IS NOT NULL`
- **RLS**: any authenticated user can read. Writes are service role only
  (upserted in the finishing transaction by the commit RPC; see §8).

Display rating formula — new player (mu=25, sigma=25/3 ≈ 8.33): display ≈ 0.
Established player (mu=30, sigma=2): display ≈ 960.

#### `rating_history` (Immutable Per-Game Rating Audit Log)

- `id` (uuid, PK)
- `user_id` (uuid, nullable fk to users, ON DELETE CASCADE)
- `bot_id` (uuid, nullable fk to bots, ON DELETE CASCADE)
- `game_id` (uuid, fk to games, ON DELETE CASCADE)
- `pool` (text)
- `mu_before`, `sigma_before` (double precision) — rating snapshot before this
  game
- `display_before` (int)
- `mu_after`, `sigma_after` (double precision) — rating snapshot after this game
- `display_after` (int)
- `display_change` (int) — signed delta (`display_after - display_before`)
- `created_at`
- **XOR constraint**: `(user_id IS NULL) != (bot_id IS NULL)`
- **Indexes**: `(user_id, pool, created_at DESC)` where `user_id IS NOT NULL`;
  `(game_id)`
- **RLS**: authenticated users can only read their own history
  (`user_id = auth.uid()`). Bot history is not readable by clients.

#### `private.app_config` (Environment Configuration)

- `key` (text, PK) — config key (e.g. `'serverless_base_url'`)
- `value` (text, NOT NULL) — config value
- `description` (text, nullable)
- `updated_at` (timestamptz)
- **Scope**: `private` schema — not exposed via the REST API. Read by
  `SECURITY DEFINER` trigger functions only. Sensitive values (secrets) belong
  in Vault, not here.
- **Local dev**: seeded via `seed.sql`. Production values are inserted via the
  Supabase dashboard or a deploy script.

### Views

**`friends_view`** is the only view in the public schema (see below). The former
`public_players` view has been replaced by the `app_players` RPC — see §7.

### `app_players` RPC

**`public.app_players(p_ids uuid[])`** — unified identity lookup for both humans
and bots:

```sql
CREATE FUNCTION public.app_players(p_ids UUID[])
RETURNS TABLE(id UUID, username TEXT, display_name TEXT, avatar_url TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT u.id, u.username, up.display_name, up.avatar_url
  FROM public.users u JOIN public.user_profiles up ON up.id = u.id
  WHERE u.id = ANY(p_ids)
  UNION ALL
  SELECT b.id, b.username, b.display_name, b.avatar_url
  FROM public.bots b
  WHERE b.id = ANY(p_ids);
$$;

REVOKE EXECUTE ON FUNCTION public.app_players(UUID[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.app_players(UUID[]) TO authenticated;
```

**Why a function, not a view?** The Supabase linter flags `SECURITY DEFINER`
views in the `public` schema. A `SECURITY DEFINER` function achieves the same
privilege bypass without the linter warning, because `SECURITY DEFINER` on a
function is the documented pattern for cross-user identity lookups.
`REVOKE EXECUTE FROM PUBLIC, anon` + explicit `GRANT TO authenticated` locks
down access.

**Scope: game-level identity only.** Returns only public-safe columns (no email,
no payment_tier). `display_name` is non-null in both branches. Cached per-ID on
the client via `playerInfoCacheProvider(id)` — `keepAlive: true` + SQLite
persistence via `@JsonPersist()`. See §23.

> **Social features do not use this RPC.** Friend requests, user search, and
> relationship management are human-only. Those features query `users` and
> `user_profiles` directly so bots never appear in search results or friend
> lists.

**`friends_view`** — symmetric convenience view with `security_invoker = on`:

```sql
CREATE OR REPLACE VIEW friends_view
  WITH (security_invoker = on)
AS
SELECT user_id_1 AS user_id, user_id_2 AS friend_id, status, initiated_by, created_at, updated_at
FROM relationships
WHERE user_id_1 = (SELECT auth.uid())
UNION ALL
SELECT user_id_2 AS user_id, user_id_1 AS friend_id, status, initiated_by, created_at, updated_at
FROM relationships
WHERE user_id_2 = (SELECT auth.uid());
```

The view is scoped to `auth.uid()` at definition time, so a simple
`SELECT * FROM friends_view WHERE status = 'accepted'` returns only the caller's
accepted friends. Realtime subscriptions must use the base `relationships`
table.

### Search Indexes

Trigram indexes (`pg_trgm`) are enabled for fuzzy user search:

- `users_username_trgm_idx` — GiST trigram index on `users.username`
- `user_profiles_display_name_trgm_idx` — GiST trigram index on
  `user_profiles.display_name`

These power the `app_search_users` RPC's `ILIKE` queries efficiently.

---

## 3. Timing System

Timing is **infra-owned** — the three game hooks never implement clock logic.
Infra reads the timing columns from `games`, applies the precedence chain, and
writes `turn_deadline`, `player_times`, and `turn_started_at` after every
action.

### Timing Modes

| Mode                  | Columns set                                              | Behaviour                                                                                                                                                                                        |
| --------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Untimed**           | both null                                                | No deadline. Players act at any pace.                                                                                                                                                            |
| **Per-action**        | `turn_seconds = N`                                       | Each turn gets a fresh N-second window, regardless of history.                                                                                                                                   |
| **Accumulated clock** | `budget_seconds = B`, optionally `increment_seconds = I` | Each player has a personal bank of B seconds. The bank drains while that player is acting. I seconds are added to the acting player's bank after each bank-consuming action (Fischer increment). |

These modes are mutually exclusive at the schema level. A `CHECK` constraint
prevents both `turn_seconds` and `budget_seconds` from being set simultaneously.

### Per-Action Action Override

Any game hook may return `"turn_seconds": N` in its response envelope to
override the deadline for **that specific action only**, without touching any
player's bank. This is for situations where a particular action phase has its
own fixed window (e.g. a 10-second Nope window in Exploding Kittens, a pre-flop
betting timer in Poker). The hook returning `turn_seconds` is the only way for
game logic to influence timing — all other clock management is fully
infra-owned.

### Deadline Precedence Chain

Applied in `engine_commit_action`, `engine_commit_start`, and the expire path
after every state change:

```
1. Game is over (outcome ≠ null)  →  deadline = NULL, turn_started_at = NULL
2. Hook returned turn_seconds N   →  deadline = NOW() + N seconds (bank untouched)
3. Budget mode (budget_seconds ≠ null), next player has remaining bank B  →  deadline = NOW() + B ms / 1000
4. Per-action mode (turn_seconds ≠ null)  →  deadline = NOW() + turn_seconds
5. Untimed  →  deadline = NULL
```

### Bank Deduction (Budget Mode)

On every commit (`engine_commit_action`) where the hook did **not** return
`turn_seconds`:

1. Compute `elapsed_ms = NOW() - turn_started_at` (transaction time — consistent
   within the call).
2. Deduct `elapsed_ms` from the acting player's bank
   (`player_times[player_index + 1]`), floored at 0.
3. Add `increment_seconds * 1000` to that player's bank (Fischer increment).
4. Set `turn_started_at = NOW()` for the incoming pending player.
5. Set `turn_deadline` based on the next pending player's remaining bank.

If the bank reaches 0 and `increment_seconds` is 0 (or null), the deadline is
set to `NOW()`. Any subsequent submit attempt by that player fails with "Turn
has expired" once the deadline plus the grace window (see below) has passed.

### Deadline Grace Window (Latency Tolerance)

Server time is measured at request **arrival** (`NOW()` = transaction start),
not when the player tapped submit, so a player's network latency is charged
against their clock. Without compensation, an action submitted on time can
arrive after the deadline and be rejected — and then the timeout path
forfeits/skips the player who actually acted on time.

To prevent this, **every deadline comparison adds a fixed grace window** of
`private.deadline_grace_ms()` (currently 750 ms). The comparison is defined
once, in `private.deadline_expired(deadline, now)`, and called from all three
places a deadline is tested so the window can never drift between them:

- `engine_commit_action` — accepts an action while `NOT deadline_expired` (i.e.
  `turn_deadline + grace >= now`).
- The expire commit (`internal/expire`) — abstains (returns without acting)
  while `NOT deadline_expired`.
- `cron_expire_turns` (cron sweep) — only enqueues games where
  `deadline_expired`.

The symmetry is essential: grace in the commit alone would still lose the race
to the timeout path. With grace on all three, the timeout path stays dormant for
exactly as long as the commit stays lenient, so an on-time-but-latent submit
reliably wins the `FOR UPDATE` lock.

**Budget mode fairness.** The grace forgives _acceptance_, not _time charged_ —
the elapsed bank deduction (floored at 0) still runs, so a player cannot gain
free thinking time by exploiting the window. In per-action mode the grace is a
genuine small extension, so it is kept small relative to typical `turn_seconds`.

**Budget-mode flag-fall (accepted behaviour).** When a bank reaches 0 the
deadline is `now`, so the grace lets a player overrun their bank by up to the
grace window and still have that final move _accepted_ (counted) rather than
timed out. This is an intentional, irreducible consequence of arrival-time
enforcement: with the server clock as the only trusted source, an honest move
delayed in transit is indistinguishable from a genuine overrun, and a
client-supplied submit timestamp cannot be trusted (it would be the obvious way
to steal time). So forgiving transit latency necessarily forgives a bounded
overrun. The leak is small and self-limiting — at most one move, and the floored
deduction means no _future_ time is gained — which is acceptable for casual
play. A competitive/rated budget mode that needs absolute flag-fall would add a
per-game opt-in that zeroes the acceptance grace once a bank is exhausted, while
keeping full grace on every non-flag turn.

#### Client Soft-Deadline Margin

The server grace is the enforcement boundary; the client additionally nudges
honest players to submit _before_ the true deadline so the grace is rarely
needed. This is display-only and never affects enforcement:

- **Per-action / hook-override** (`TurnCountdown`): the displayed countdown
  reaches zero `softMargin` early, where `softMargin = min(1s, 25% × window)`
  and `window = turn_deadline − turn_started_at`. The cap prevents a short
  window (e.g. a 3 s Nope) from being swallowed.
- **Budget mode** (`BudgetClock`): the clock stays truthful — subtracting a
  margin would make a chess-style clock snap back up on submit. Instead the
  local player's own active cell shows a "Submit!" cue once their bank enters
  the final-headroom zone.
- **Untimed**: no deadline, no margin.

The constants live in `lib/core/game/timing_constants.dart`
(`kServerDeadlineGrace`, `kSoftDeadlineMargin`, `kSoftDeadlineMaxFraction`) and
are hardcoded to mirror `deadline_grace_ms()` — keep the two in sync.

### Timeout Handling

The pg_cron sweep `cron_expire_turns` selects any game where
`turn_deadline + grace < NOW()` and `pg_net`-wakes the `internal/expire` route
with the batch. For each game the EF:

1. Reads the state and runs `applyLifecycle({"type":"timeout"})` **once**. Every
   pending seat shares the single deadline, so all of them timed out; the hook
   resolves the whole set holistically (eliminate, skip, fold, or even a draw)
   and returns one envelope.
2. Commits that single **identity-less `system` transition** through
   `engine_commit_action` (`p_mode = 'timeout'`), which acquires a `FOR UPDATE`
   lock and re-checks expiry via `private.deadline_expired` against the same
   grace window (guards against a concurrent commit that wins the lock during
   the grace window — the commit abstains and leaves the turn live).
3. In budget mode, zeroes **every** pending seat's bank
   (`player_times[seat + 1] := 0`).
4. Applies the same deadline precedence chain for the next turn.

The action row carries no performer identity (`user_id`/`bot_id`/`player_index`
all NULL); which seats were affected is recoverable from the `pending_players`
diff. There is no per-seat batch — one timeout event is one state version.

### Budget Mode Requires Sequential Pending

Budget clocks are a sequential concept by nature. The whole point of an
accumulated clock is to meter _individual thinking time_ — how long each player
spends deliberating before they commit. This only has meaning when players act
one at a time. It does not have a clean meaning when multiple players are
pending simultaneously, for two reasons:

**One deadline cannot meter many independent clocks.** A state carries a single
`turn_deadline`, but a budget clock is a per-player countdown that drains only
while that player acts. With multiple simultaneous pending players there is no
single deadline that faithfully represents N independently-draining banks: when
it fires, some players may be out of time while others still have bank, and the
elapsed charge differs per player. (The holistic timeout _resolution_ is fine —
the hook sees the whole pending set and decides fairly — but the _bank
accounting_ still has no clean meaning, which is why budget mode is restricted
to one pending seat at a time. The harness enforces this at the source:
`assertBudgetPending` runs next to `assertHookState` after every hook and 500s
an envelope with more than one pending seat in a budget-timed game.
`compute_next_deadline` keeps a best-effort MIN-over-pending safeguard as the
SQL backstop.)

**The pairing doesn't occur in real games.** Accumulated clocks exist in
deliberative sequential games (chess, correspondence Go) where thinking time is
the scarce resource. Simultaneous-commitment games (RPS, secret bidding, poker
showdowns) are inherently fast and action-oriented — the natural choice there is
a per-action timer or no timer at all. No game in the target list combines the
two.

**Rule for implementors:** if your game has any phase where `pending_players`
contains more than one index, do not use `budget_seconds`. Use `turn_seconds`
(per-action) for those phases, or return `"turn_seconds": N` from the hook for
that specific action to give all pending players a shared fixed window. Budget
mode is reserved for games where exactly one player is pending at any given
time — a hook that returns a multi-seat pending set in a budget-timed game is
rejected as a game bug (500) before commit.

### Client-Side Display

Clients receive all timing fields through their `observations` Realtime
subscription — no extra queries needed:

- `turn_deadline` → countdown timer (works for all modes)
- `player_times` + `turn_started_at` → live accumulated clock per player

```dart
// Live remaining budget for the active player (budget mode only):
final elapsed = DateTime.now().difference(obs.turnStartedAt!).inMilliseconds;
final remaining = obs.playerTimes![myPlayerIndex] - elapsed;
```

> **Known limitation — device clock skew.** All countdowns compare server
> timestamps (`turn_deadline`, `turn_started_at`) against `DateTime.now()`. A
> device with a skewed clock displays a wrong countdown and may fire the
> `game/expire` nudge early (harmless — the server re-validates under lock and
> abstains during the grace window) or late (the pg_cron backstop catches it).
> Enforcement is never affected; only the displayed value is. The server grace
> window and client soft margin (above) absorb modest skew on the submit path; a
> future fix would estimate a server-time offset from `observations.updated_at`
> at receipt and apply it in the timer builders.

#### Client-Side Expiry Trigger

The game screen maintains a `_deadlineTimer` (`dart:async Timer`) scheduled to
fire at `turn_deadline + kExpiryTriggerDelay` — i.e. ~1 s _past_ the deadline,
deliberately beyond the server grace window (`kExpiryTriggerDelay` =
`kServerDeadlineGrace` + a 250 ms skew/jitter epsilon). Firing at the deadline
itself would hit the server while it is still abstaining, the nudge would no-op,
and the timeout would slip to the coarse pg_cron sweep. The delay only affects
the AFK/timeout path; a player who acts is never delayed by it.

On fire it calls the `game/expire` route — a safe, idempotent nudge that lets
the server process the timeout before pg_cron runs (which may fire on a coarse
schedule). The server re-validates under `FOR UPDATE` lock, so concurrent calls
from multiple active clients are safe.

Any active participant — not just the player whose time ran out — should trigger
expiry. If Player A times out but has the app backgrounded, Player B's client
drives the expiry immediately.

#### Client-Side Timing Widget System

The timing widget stack follows the **builder pattern** — computation is
separated from rendering so game implementors can style clocks however they
want.

**Computation layer** (`timer_builders.dart`):

| Widget               | Purpose                                                                                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `TurnTimerBuilder`   | Owns a `Timer.periodic(1s)`, ticks toward a deadline, self-cancels at zero. Exposes `Duration remaining` to a `builder` callback.                                                                |
| `PlayerTimerBuilder` | Owns a `Timer.periodic(1s)`, computes one player's remaining budget (live drain for the active player, static for inactive). Exposes `(int remainingMs, bool isActive)` to a `builder` callback. |

**Infra-owned styled shells**:

| Widget          | Wraps                         | Display                                                                                     |
| --------------- | ----------------------------- | ------------------------------------------------------------------------------------------- |
| `TurnCountdown` | `TurnTimerBuilder`            | `"12m 34s"` / `"45s"`, error-red under 60 s. `StatelessWidget`.                             |
| `BudgetClock`   | `PlayerTimerBuilder` per cell | Row of `"M:SS"` cells, one per player. Each cell rebuilds independently. `StatelessWidget`. |

**Infra-owned header** (`_TimingHeader` in `game_screen.dart`): auto-dispatches
on timing mode — `BudgetClock` if `game.budgetSeconds != null`, `TurnCountdown`
if `turnDeadline != null`, nothing if untimed. Shown above the game content
widget.

**`TimingContext`** (`core/game/timing_context.dart`): passed as a required
argument to `GameRules.buildContent`. Carries `playerTimes`, `turnStartedAt`,
and `turnDeadline` from the latest observation so game content widgets can
render custom timing UI without depending on Riverpod providers directly.

Game implementors who want custom clock placement (e.g. Chess showing each
player's clock next to their captured pieces) use `TurnTimerBuilder` /
`PlayerTimerBuilder` directly with `timingContext` values. See the Game
Implementation Guide §Timing Widgets for examples.

#### Known Limitation — Budget Mode + Hook-Override `turn_seconds`

When a hook returns `turn_seconds` for a specific action inside a budget mode
game (e.g. an Exploding Kittens–style Nope interrupt window where multiple
players are simultaneously pending), the `_TimingHeader` still shows
`BudgetClock` because `game.budgetSeconds != null`. The `PlayerTimerBuilder`
marks every player in `pendingPlayers` as "active" and visually drains their
banks, but the server is using the hook's fixed window — not touching any
player's bank. The display is misleading for that phase.

The root cause is that the client cannot distinguish between a bank-consuming
deadline and a hook-override deadline from the observation fields alone. A
correct fix requires the server to include a `deadline_type` field (e.g.
`"budget"` vs `"hook_override"`) in the `observations` row so the client can
switch to a shared `TurnCountdown` for hook-override phases. Until that schema
change is made, games that combine budget mode with hook-override `turn_seconds`
on multi-player-pending phases should be aware of this visual inaccuracy.

---

## 4. Game Hooks (Infra ↔ Game Contract)

The entire game-specific rules surface is a **TypeScript `GameModule`: one
`GameRules` unit per `schema_version`, each bundling six hooks + the Zod
payload schemas** (the app's rules module, vendored into the edge function).
Replacing it produces a completely different game with no other changes. The
interfaces and their argument/return types live in
`supabase/functions/_types/engine.types.ts`; the edge function resolves the
game row's version unit (`rulesFor` in `_engine/game-engine.ts`), calls its
hooks at the commit chokepoint, and persists the result atomically via the
gated SQL RPCs.

All hooks receive a `HookContext` (`config`: the game blob, parsed against the
unit's own config schema). No hook receives a version — a `GameRules` unit is
version-specific by construction, so hooks never branch on it.
`initialState`, `applyAction`, and `applyLifecycle` return an **`Envelope`**;
`applyAction` additionally rejects a rule-breaking move by throwing
`IllegalMoveError` (rendered as a 400 — the hook's one expected failure).

The **`Envelope`** is
`{ state, pending_players, outcome?, turn_seconds? }`:

- `state`: pure game payload (board, deck, fog…). Never whose-turn or winner
  info — those are infra columns.
- `pending_players`: 0-based seats that may act next. Empty ⇒ game over.
- `outcome?`: **omit while ongoing** (infra treats absent as SQL `NULL`);
  present only when the game ends, as `OutcomeEntry[]` (see below).
- `turn_seconds?`: per-action deadline override for **this action only** (does
  not touch any bank). Omit to use the game's configured timing.

Randomness never rides the envelope. The three envelope-producing hooks instead
receive **`args.rng`** — a deterministic per-transition generator (`rand-seed`
sfc32) the harness derives from the game's stored base seed and the state
version the envelope will commit as. Draw freely (`rng.next()` → float in
`[0, 1)`, stateful within the invocation); the same transition always
re-derives the same sequence, so a game stays a pure function of (base seed,
action log) as long as hooks draw in deterministic code order.

### `botSeatable(args: BotSeatableArgs): boolean`

Optional. The edge function calls this before seating a bot (the `add-bot` and
`create-solo` routes) to decide whether a bot may join a game with the chosen
`config`. `args` carries `botConfig` (the bot's declared capabilities) and
`gameConfig`. Return `true` to allow. This is the **single source of truth** for
config compatibility; the same version's Dart `GameRules` keeps a **twin** that filters the
bot pickers locally, so the rule is never re-encoded by hand. Default: `true`.
Gates the variant axis `schema_version` cannot (a bot can match the schema yet
not support the rules variant).

### `ratingPool(args: RatingPoolArgs): string | null`

Decides whether — and in which pool — a game with these settings is rated.
Returns a pool name (e.g. `'rapid'`, `'daily'`) or `null` for unrated.

The edge function computes `canBeRated = pool != null && !guest` and validates
the client's concrete **`rated` assertion** against it — **rejecting a mismatch
(422)** rather than coercing. There is no _forced-rated_ mode (only
forced-unrated and toggle). The same version's Dart `GameRules` keeps a **twin** so the create
dialog gates the Rated/Casual toggle and sends the same value the server will
compute. See the Game Implementation Guide §Hook 0 for the full contract and an
example override.

### `initialState(args: InitialStateArgs): Envelope`

`args`: `rng`, `playerCount`, plus the `HookContext`. Returns the starting
envelope, e.g.:

```jsonc
{
  "state": {/* starting payload */},
  "pending_players": [0]
}
```

`pending_players` are the seats that may act first; draw any setup randomness
(deck shuffle, first player…) from `args.rng`; `turn_seconds` optionally fixes
the first action's deadline.

### `applyAction(args: ApplyActionArgs): Envelope`

`args`: `state`, `pending`, `data` (the move), `playerIndex`, `rng`, plus the
`HookContext`. The infra has **already** confirmed it is this seat's turn at the
expected version under the row lock, so do **not** re-check turn order — only
validate move legality. Throw `IllegalMoveError` for a rejected move (→ 400 with
the message); return the new envelope for a legal one.

When the game ends, include `outcome` as an array of `OutcomeEntry`:

```jsonc
[
  { "player_index": 0, "result": "win", "placement": 1, "team_index": 0 },
  { "player_index": 1, "result": "loss", "placement": 2, "team_index": 1 }
]
```

Required: `player_index`, `result` (`"win"`|`"loss"`|`"draw"`|`"eliminated"`),
`placement` (1 = best, ties share a value), `team_index` (use `player_index` for
individual games). Optional `score`. Infra writes these to `game_outcomes`, sets
`games.status = 'finished'`, and — if rated — applies rating updates in the same
transaction. See §8 for team examples.

### `applyLifecycle(args: ApplyLifecycleArgs): Envelope`

`args`: `state`, `pending`, `type` (`'forfeit'` | `'timeout'`), `data`, `rng`,
plus the `HookContext`. Decides the consequence of a **lifecycle action** — the
engine-owned species of action (see `actions.kind`), operating on the game
from outside its rules; unlike `applyAction` it **cannot be illegal** — it
always resolves to an envelope (the game decides whether a forfeit/timeout
ends the game or just advances past the seat). Called by the forfeit/expire
routes and the account-deletion / stale-guest purge paths.

### `computeObservation(args: ComputeObservationArgs): ObservationSlice`

`args`: `state`, `pending`, `playerIndex`, `participantCount`, `isReplay`, plus
the `HookContext`. Returns `{ data, pending_players }` — this seat's permitted
view, with `pending_players` optionally narrowed for hidden-info games (e.g. a
Nope window). The edge function fans this out per participant after every
transition, and per historical version for replay. `isReplay` is `true` only
when projecting a **finished** game for replay, so hidden-info games may reveal
opponent state post-game.

**Perfect-info games do not override this** — a `passthroughObservation` helper
provides the identity projection.

---

## 5. Entry Points — Edge Function Routes & RPCs

There are **two tiers** of server entry point:

1. **Edge-function routes** — the primary surface for everything that needs the
   game rules or an un-forgeable policy gate. The Dart client calls them across
   the `engine` function's route groups (`game`, `social`, `internal`, `bot` —
   see §21). Each route runs in TypeScript: a **Zod request schema** on the
   route validates the body shape (a malformed request 400s before any handler
   runs), the handler verifies the caller, resolves the game row's
   `schema_version` unit from `GameModule.versions`, parses every game payload
   (state, action data, config) through **that unit's Zod schemas** — so hooks
   receive typed, validated values and the state a hook returns is re-validated
   before commit — runs the relevant `GameRules` hook(s), and calls a
   **service-role, gated `engine_*`
   SQL RPC** for the atomic write through `_engine/repo.ts`, the single module
   that touches the database. **Policy lives in TS** (request validation, the
   schema boundary, guest gating from the JWT `is_anonymous` claim, the rating
   decision); the `engine_*` RPCs are **thin atomic writers** that keep only the
   lock/transaction work, backed by the `games` CHECK / `UNIQUE` / FK
   constraints. These RPCs are `REVOKE`d from `authenticated` — only the edge
   function (service role) may call them.
2. **Client-direct RPCs** — latency-sensitive reads and lobby state operations
   the Dart client calls **straight over PostgREST** under its own JWT
   (`auth.uid()`
   - RLS). There is **no edge function in the loop**, so the SQL function _is_
     the server-side gate and its policy stays in SQL.

**Function naming (by tier).** The prefix tells you who may call it:

- **`engine_*`** — service-role, **edge-function-only** gated RPCs (`REVOKE`d
  from `authenticated`); the EF's atomic-writer surface.
- **`app_*`** — **client-direct** RPCs the Dart app calls over PostgREST under
  RLS/auth.
- **`cron_*`** — `private`, pg_cron-scheduled sweeps (scheduled in the
  `cron_jobs` migration).
- **`do_*`** / other `private.*` — internal helpers; `do_*` are parameterized
  cores shared by an `app_*` wrapper (binds `auth.uid()`) and an internal caller
  (e.g. `engine_purge_user`).

Clients only ever call `app_*` RPCs; views (e.g.
`private.open_games_with_participants`) stay private implementation details
behind them. Triggers (`handle_new_user`, …) carry no tier prefix. The infra SQL
is split by tier across dependency-ordered migrations (`…_engine_helpers`,
`…_engine_commit`, `…_engine_games`, `…_engine_lifecycle`, `…_app_lobby`,
`…_app_social`), with cross-cutting types and extensions defined first in
`…_foundation.sql`.

### Edge-function routes

| Route                                                       | RPC it commits through                                                                 | Purpose                                                                                                                                                                                                                                                                            |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `game/create`                                               | `engine_create_game`                                                                   | Creates the `games` row (unique `short_code` retry) + seats the creator as participant 0. EF validates timing/players/access, blocks guests from `friends` access, derives the pool (`ratingPool`), and **validates the client's `rated` assertion** (rejects a mismatch).         |
| `game/create-solo`                                          | `engine_create_solo_game`                                                              | Atomic **sole-human, unrated, private** game; seats caller + bots full at creation (never joinable). EF gates bot class: `botSeatable`, schema compat, guests ⇒ local bots only, **server ⇒ timed / local ⇒ untimed**.                                                             |
| `game/add-bot`                                              | `engine_add_bot_to_game`                                                               | Creator-only waiting-room fill with a **server** bot. EF rejects guests + checks `botSeatable`; SQL holds the `FOR UPDATE` lock for the creator check, seat-count cap, and the server-only/schema/`rated_eligible` invariants (`seat_server_bot`).                                 |
| `game/start`                                                | `engine_commit_start`                                                                  | `initialState` → writes `game_states` v0 + per-seat `observations`, inits banks (budget mode), sets `turn_started_at`, marks `active`. Creator-only, under lock.                                                                                                                   |
| `game/action`                                               | `engine_commit_action`                                                                 | The move chokepoint. EF runs `applyAction`; SQL row-locks `games`, validates version + deadline under lock, gates on `pending_players`, deducts bank, fans out observations, and on finish writes `game_outcomes` + rating updates **in the same transaction**.                    |
| `game/forfeit`                                              | `engine_commit_action` (`resign`)                                                      | A user resign → `applyLifecycle('forfeit')`, logged as a `user` action (carries the resigning user + seat). No deadline/pending guard (resign any time, even off-turn); version-checked under the lock and retried on stale.                                                          |
| `game/expire`                                               | `engine_commit_action` (`timeout`)                                                     | Client nudge when it detects the deadline passed → `applyLifecycle('timeout')` over the whole pending set, one identity-less `system` action. The server re-validates expiry under lock (abstains if a real action won the race). Same core as the cron backstop (`internal/expire`). |
| `game/replay`                                               | _(typed SDK read)_                                                                     | The caller's observation slice at every version, projected through `computeObservation` — never raw state. The EF reads `game_states` with each producing `action` embedded (via the `actions→game_states` FK) and applies the finished-only + participant gate **in TS**.         |
| `game/local-bot-action`                                     | `engine_commit_action` (`bot`)                                                         | Drives a **local** bot seat. EF gates in TS against the roster it read (`assertLocalBotSeat`: caller is a participant, seat is a local bot, sole-human game).                                                                                                                      |
| `game/delete-account`                                       | `engine_purge_user` (+ per-game forfeits)                                              | Self-service account teardown — see §22.                                                                                                                                                                                                                                           |
| `social/friend-request` · `social/accept` · `social/remove` | `engine_send_friend_request` · `engine_accept_friend_request` · `engine_remove_friend` | Friend writes. EF gates the **caller** (registered-only, no self-request) from the JWT and pushes the FCM notification directly; SQL keeps the atomic relationship write and the **target**-anonymity check (needs the target's row).                                              |
| `internal/expire` · `internal/purge-users`                  | `engine_commit_action` · `engine_purge_user`                                           | Batched cron paths (secret-API-key auth) — timeout sweep and stale-guest forfeit-then-purge. See §21 / §22.                                                                                                                                                                        |
| `bot/action`                                                | `engine_commit_action` (`bot`)                                                         | A **server** bot's only surface. The per-bot HMAC over the payload is verified in TS (`_engine/bot_auth.ts`, keyed by `HMAC(BOT_SIGNING_SECRET, bot_id)`); then the claimed seat is checked and the move applied.                                                                  |

### Client-direct RPCs (PostgREST, `authenticated`)

| RPC                                                  | Purpose                                                                                                                                                                                                                                                                                                                                                                                 |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `app_join_game(game_id, client_schema_version)`      | Seats a human under `FOR UPDATE`: rejects at `max_players`, transitions to `ready` at `min_players`, enforces the `friends`-access relationship check, and refuses to seat when `games.schema_version` exceeds the client's `client_schema_version` (so a client never joins a game it cannot render). The schema parameter is required. Rejects a guest joining a rated game. See §24. |
| `app_join_game_by_code(code, client_schema_version)` | Resolves a `short_code`, then delegates to `app_join_game` (forwarding the schema gate).                                                                                                                                                                                                                                                                                                |
| `app_cancel_game(game_id)`                           | Creator aborts a `waiting`/`ready` game (`status = 'aborted'`).                                                                                                                                                                                                                                                                                                                         |
| `app_leave_game(game_id)`                            | Non-creator leaves a `waiting`/`ready` game; compacts higher `player_index`es under the lock; demotes `ready` → `waiting` below `min_players`. Creator must cancel instead.                                                                                                                                                                                                             |
| `app_lobby_games(cursor, limit)`                     | Public waiting/ready games with embedded participants, cursor-paginated by `created_at`. `authenticated` only.                                                                                                                                                                                                                                                                          |
| `app_friends_games(cursor, limit)`                   | `friends`-access waiting/ready games created by the caller's accepted friends, plus the caller's own rooms; not-full only; cursor-paginated.                                                                                                                                                                                                                                            |
| `app_search_users(query)`                            | Up to 20 human-only results matching `username`/`display_name` (trigram `ILIKE`). **Registered-only** (`require_permanent_user`); excludes anonymous accounts.                                                                                                                                                                                                                          |
| `app_local_bot_observation(game_id, player_index)`   | A local bot seat's **full** observation so the sole human's client can run the AI. Gated (sole human + local-bot seat) — the only place the engine reveals a bot's hidden view to a client.                                                                                                                                                                                             |
| `app_bots()`                                         | The bot catalog for the pickers — display-safe columns + `config` (never `webhook_url`).                                                                                                                                                                                                                                                                                                |
| `app_players(...)`                                   | Embedded participant identity for a set of games.                                                                                                                                                                                                                                                                                                                                       |
| `app_update_username(new_username)`                  | Validates format + case-insensitive uniqueness, updates `users.username`.                                                                                                                                                                                                                                                                                                               |

> The Dart `GameRules` units keep **local twins** of `ratingPool` and `botSeatable`,
> so the create dialog gates the Rated/Casual toggle and the bot pickers filter
> their lists without any extra RPC (the old `preview_game_rating` /
> `seatable_bot_ids` RPCs are gone). The server remains authoritative — it
> recomputes and validates on the write.

### Version Conflicts

`engine_commit_action` is guarded by an optimistic lock: the client passes the
`version` it last observed, and the RPC raises `Stale state: …` under the row
lock if another writer committed first. (The `action` route also does a
non-authoritative fast-fail against the state it already read, to skip a doomed
commit.) The client does not retry automatically — it surfaces a humanized
"board updated — try again" message (`error_messages.dart`), letting the player
re-act against the state the Realtime stream has by then delivered.

> Simultaneous games (multiple players pending in one round) will hit this
> routinely with spurious conflicts; handling that is tracked in
> `future_plans.md`.

### Client Query Patterns (Not RPCs)

The Dart client uses PostgREST embedded selects for efficient single-round-trip
queries:

- **Active games dashboard**: `games` with embedded
  `participants!inner(user_id, player_index)` and
  `observations(pending_players, turn_deadline)` — derives `myPlayerIndex`,
  `pendingPlayers`, and `turnDeadline` in one query.
- **Public lobby**: `app_lobby_games(cursor)` RPC returns public waiting/ready
  games with embedded participants. Cursor-paginated by `created_at` with page
  size 50.
- **Friends lobby**: `app_friends_games(cursor)` RPC returns friends-access
  games. The lobby screen uses a swipeable `TabBar` + `TabBarView` to switch
  between public and friends modes; each tab widget uses
  `AutomaticKeepAliveClientMixin` so the paged list is retained on tab switch
  without a re-fetch.
- **History**: `games` filtered to `finished` / `aborted` status, with embedded
  `participants!inner`, `game_outcomes`, and `rating_history` — derives
  `myResult` and the current user's `RatingChange?` per game in a single query.
  RLS on `rating_history` automatically filters embedded rows to the current
  user, so no explicit user filter is needed. Cursor-paginated by `finished_at`
  descending with page size 30.

---

## 6. Hidden Information

`game_states` is service-role only. Clients never see the ground truth directly.
Each player receives only their personal `observations` row, which is computed
by `computeObservation` after every state change. This makes hidden-info games
(Poker, Literature, Exploding Kittens, Mafia) structurally secure — the server
computes each player's slice and Realtime pushes only that slice to the right
subscriber.

RLS on `observations` (`user_id = auth.uid()`) means a client subscribing to
`game_id = X` receives at most one row — their own.

---

## 7. Player Identity System

Player identity is resolved and cached independently from game-specific data,
ensuring usernames and avatars are available across all screens without
redundant network calls.

### Scope: Game Identity vs Social Identity

|                  | Game identity (`app_players` RPC)                                                                                                                               | Social identity (base tables)                    |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **Covers**       | Humans and bots                                                                                                                                                 | Humans only                                      |
| **Used by**      | `playerInfoCacheProvider`, `gamePlayers`, lobby/game display                                                                                                    | `app_search_users`, friend RPCs, relationship UI |
| **Source**       | UNION of `users`+`user_profiles` and `bots`                                                                                                                     | `users` and `user_profiles` directly             |
| **Why separate** | In a game, the seat holder may be a bot — it needs a name and avatar. In social contexts, bots are not people and cannot be friended, searched for, or invited. |                                                  |

### Data Flow

```
app_players(uuid[]) RPC (DB) ← unified UNION of users+bots
       ↓
playerInfoCacheProvider(id)  ← keepAlive + SQLite persist, works for any player UUID
       ↓
gamePlayersProvider(gameId)  ← fetches participants, resolves identities
       ↓
PlayersContext                ← passed to buildContent()
 └── Map<int, GamePlayer>    ← playerIndex → {type, info}
```

### Models

**`PlayerInfo`** (`shared/data/models/player_info.dart`) — canonical public
player identity for both humans and bots:

- `id` (String) — user or bot UUID
- `username` (String)
- `displayName` (String?)
- `avatarUrl` (String?)

The bot/human distinction is carried by `GamePlayer.type`
(`ParticipantType.human` or `ParticipantType.bot`), not by the identity model.
`app_players` returns the same columns for both branches of its UNION, so
`PlayerInfo.fromJson` parses both identically.

**`GamePlayer`** (`core/game/game_player.dart`) — unified game-level player
concept:

- `playerIndex` (int) — 0-based seat
- `type` (ParticipantType)
- `info` (PlayerInfo) — resolved identity

(Per-game roles are not modelled here — they live in the game's observation/
state JSON, interpreted by the game module.)

**`PlayersContext`** (`core/game/players_context.dart`) — passed to
`buildContent`:

- `players` (Map<int, GamePlayer>) — all players keyed by index
- `myPlayerIndex` (int) — current user's seat (-1 if spectating)
- `operator [](int)` → `GamePlayer` — non-nullable access
- `me` → `GamePlayer` — convenience accessor

### Provider Architecture

`playerInfoCacheProvider(id)` is `keepAlive: true` + `@JsonPersist()`. Works for
both human and bot IDs — `app_players` covers both via a UNION. On cold start,
resolves from SQLite cache (~5 ms) while the network fetch runs in background.
Held in memory for the entire session after first access. See §23 for the full
persistence design.

`gamePlayersProvider(gameId)` is auto-dispose — a session touches many games
(home cards, history navigation), and keeping every game's context alive forever
would grow without bound. Re-fetching is cheap because identities resolve from
the persisted `playerInfoCacheProvider`; only the participants query runs. It
fetches participants, resolves each identity via
`playerInfoCacheProvider(id: p.userId ?? p.botId!)` in parallel (XOR constraint
guarantees one is non-null), assembles `GamePlayer` objects, and returns a
complete `PlayersContext`. The game screen shows a loading indicator until this
resolves, then calls `buildContent()` with guaranteed non-nullable data.

### Cross-Screen Availability

| Screen    | How it uses player identity                                                                                                         |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Lobby** | Watches individual `playerInfoCacheProvider(id)` per participant (inline from RPC). Pre-warms the cache for game screen navigation. |
| **Home**  | Watches `gamePlayersProvider(gameId)` per game card. Extracts `PlayerInfo` for `OverlappingAvatars`.                                |
| **Game**  | Watches `gamePlayersProvider(gameId)`. Passes `PlayersContext` to `buildContent()`. Pre-game waiting room uses same data.           |

### Profile Picture Updates

When a user updates their avatar, display name, or username via
`CurrentUserProfile`, `ref.invalidate(playerInfoCacheProvider(id: userId))` is
called automatically — so game screens, lobby cards, and friend lists reflect
the change immediately without waiting for a cold start.

### Shared Widgets

- `PlayerAvatar` — displays avatar with network image caching, person-icon
  fallback, and optional border. `onTap` is optional; when `null` the widget is
  fully non-interactive (no `GestureDetector`). In `ListTile` contexts leave
  `onTap` unset — `ListTile.onTap`'s `InkWell` covers the whole row including
  the leading avatar. Pass `onTap` only when the avatar is used standalone (e.g.
  a standalone tappable icon outside a list tile).
- `OverlappingAvatars` — renders a row of overlapping `PlayerAvatar` circles for
  game cards.
- `PlayerProfileSheet` — modal bottom sheet showing a player's public profile:
  identity header, ratings across all pools, and friendship actions (humans
  only). Open via `PlayerProfileSheet.show(context, playerId: id, type: type)`.
  Bot profiles show identity and ratings with no social section. When
  `playerInfoCacheProvider` fails (e.g. deleted account), the sheet shows
  `_DeletedPlayerHeader` — a tombstone icon with "Player not found" and "This
  account no longer exists." — instead of an error string.
- `EmptyStateView` — illustrated empty state for list screens. Renders a 96×96
  icon in a `primaryContainer` circle, a `titleLarge` heading, a `bodyLarge`
  subdued message, and an optional call-to-action button. Use `tonalCta: true`
  for soft nudges (`FilledButton.tonal`), false (default) for primary creation
  actions (`FilledButton`). Used by all five list screens: Home, Lobby, History,
  Friends, and Friend Requests.

---

## 8. Rating System

The rating system uses **OpenSkill** (a Bayesian algorithm similar to TrueSkill)
to rank players. Ratings are stored in `player_ratings` (current state) and
`rating_history` (immutable per-game log), keyed by player and pool (e.g.
`'rapid'`, `'daily'`).

### Rating Parameters

Each player's skill is a Gaussian: `mu` (mean, default 25.0) and `sigma`
(uncertainty, default `25.0 / 3.0 ≈ 8.33`). The conservative **display rating**
is:

```
display_rating = max(0, round((mu − 3 × sigma) × 40))
```

A new player (mu=25, sigma=25/3) displays 0 — a deliberately conservative
estimate. As sigma shrinks with each game, the display rating reflects actual
skill more closely.

### Required Outcome Fields

Both `placement` and `team_index` are `NOT NULL` on `game_outcomes`. Every
outcome entry in the array returned by the game hooks must supply them:

| Field        | Description                                                                                                                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `placement`  | Ordinal finish rank (1 = best). Ties share the same value. Passed directly to OpenSkill as the rank input.                                                                                       |
| `team_index` | Groups players into rating teams. Players sharing a value move together. Use `player_index` for individual games (each player is their own team of one); teammates share a value for team games. |

**Individual 1v1 win/loss:**

```json
[
  { "player_index": 0, "result": "win", "placement": 1, "team_index": 0 },
  { "player_index": 1, "result": "loss", "placement": 2, "team_index": 1 }
]
```

**1v1 draw:**

```json
[
  { "player_index": 0, "result": "draw", "placement": 1, "team_index": 0 },
  { "player_index": 1, "result": "draw", "placement": 1, "team_index": 1 }
]
```

**2v2 team game (e.g. Literature / Canadian Fish):**

```json
[
  { "player_index": 0, "result": "win", "placement": 1, "team_index": 0 },
  { "player_index": 2, "result": "win", "placement": 1, "team_index": 0 },
  { "player_index": 1, "result": "loss", "placement": 2, "team_index": 1 },
  { "player_index": 3, "result": "loss", "placement": 2, "team_index": 1 }
]
```

**N-player with bust-out placements (Poker):**

```json
[
  { "player_index": 0, "result": "win", "placement": 1, "team_index": 0 },
  {
    "player_index": 2,
    "result": "eliminated",
    "placement": 2,
    "team_index": 2
  },
  {
    "player_index": 1,
    "result": "eliminated",
    "placement": 3,
    "team_index": 1
  },
  { "player_index": 3, "result": "loss", "placement": 4, "team_index": 3 }
]
```

Individual games are the degenerate case of the team model — each player is
their own team of one. OpenSkill's `rate()` handles both uniformly.

### Production Configuration

Two values must be set once per environment before the rating pipeline is
active. Local dev is handled automatically by `seed.sql` via
`supabase db reset`.

**1. `serverless_base_url` — insert into `private.app_config`**

Run in the Supabase SQL editor (replace the URL with your project's edge
function base URL):

```sql
INSERT INTO private.app_config (key, value, description)
VALUES (
  'serverless_base_url',
  'https://<project-ref>.supabase.co/functions/v1',
  'Base URL for serverless functions'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

**2. `secret_api_key` — create in Vault**

The cron sweeps authenticate to the engine EF's `/engine/internal/*` routes with
the project's **secret API key** (`sb_secret_…`, from **Settings → API Keys**)
sent as the `apikey` header; `@supabase/server`'s `auth: 'secret'` mode
validates it against the `SUPABASE_SECRET_KEY` the platform injects into the
function. There is no bespoke webhook secret to generate — the platform
credential is the credential; Vault just makes it readable from SQL.

Option A — Supabase Dashboard: **Database → Vault → Add secret**. Set name to
`secret_api_key` and value to the project's secret API key.

Option B — Supabase SQL editor:

```sql
SELECT vault.create_secret(
  'sb_secret_...',
  'secret_api_key',
  'Project secret API key; apikey header for cron -> engine EF calls'
);
```

To update an existing Vault secret (e.g. after rotating the API key):

```sql
SELECT vault.update_secret(
  (SELECT id FROM vault.secrets WHERE name = 'secret_api_key'),
  'sb_secret_...',
  'secret_api_key',
  'Project secret API key; apikey header for cron -> engine EF calls'
);
```

### Update Pipeline

Ratings are computed and persisted **inline in the finishing transition** —
there is no rating trigger, no separate function, and no async hop:

```
applyAction / applyLifecycle returns an outcome  (rated game)
        ↓  edge function (game/action, forfeit, expire, …)
readRatingsForSeats   → each seat's current (mu, sigma) for the pool
   (typed player_ratings fetch; identities from the in-hand roster,
    never-rated seats default to openskill rating())
        ↓
_engine/ratings.ts          → OpenSkill rate(teams, {rank: placements})
        ↓  RatingUpdate[] threaded onto the commit transition
engine_commit_action → private.persist_transition
        ↓  SAME transaction as the finish
player_ratings (upsert) + rating_history (insert)   (private.apply_rating_updates)
```

1. On a finishing transition of a **rated** game (`outcome` present, ≥ 2
   players), the edge function fetches each participant's `(mu, sigma)` for the
   pool from `player_ratings` (`readRatingsForSeats`) — a typed query keyed on
   the identities already in the in-hand roster, defaulting a never-rated seat
   to openskill `rating()`.
2. `_engine/ratings.ts` groups players by `team_index`, calls OpenSkill's
   `rate(teams, {rank: placements})`, and returns `RatingUpdate[]` with
   before/after snapshots. Pure computation.
3. The updates ride the commit transition into `engine_commit_action`, and
   `private.persist_transition` writes `player_ratings` + `rating_history` in
   the **same transaction as the finish** (via the now-private
   `private.apply_rating_updates`). Same "EF computes, the commit RPC persists
   atomically" pattern as observations.

### Idempotency

`rating_history` unique partial indexes — `(game_id, user_id)` and
`(game_id, bot_id)` — ensure ratings are never double-applied: a second write
for the same game is rejected at the DB level. Because the write rides the same
transaction as the `finished` transition (which is itself guarded by the
optimistic version/lock in `engine_commit_action`), a game can only finish once.

> **Known limitation — concurrent rated finishes.** The `(mu, sigma)` inputs are
> read just before the finishing commit, not under a lock on `player_ratings`.
> If two rated games involving the same player finish near-simultaneously, both
> can read the same "before" rating and the later write overwrites the earlier —
> one game's rating effect is lost. Closing this would require locking and
> recomputing from the stored values at write time. Accepted for now: the window
> is milliseconds wide and one player cannot realistically finish two games at
> once.

### Bots & Multi-Seat Results

A single bot identity may hold several seats of one game (see §26). The
`rating_history` unique index `(game_id, bot_id)` permits **one** history row
per identity per game, so `_engine/ratings.ts` collapses those seats into a
**single net update**: it chains the seat results in seat order onto a running
rating, each seat rated only against the _other_ distinct identities (never the
identity's own other seats). Both a strong and a weak seat-result contribute —
the right signal for a bot's skill. The one accepted caveat is that same-game
results are correlated, so the identity's σ shrinks slightly faster than from
independent games — immaterial for bot calibration. Bot rating history is never
client-readable (RLS).

### Rating Pools

The `GameModule.ratingPool` hook (§4) derives the pool name — a string like
`'rapid'`, or `null` for unrated. The same version's Dart `GameRules` keeps a **twin** of it
so the create dialog can show a live **Rated / Casual** badge and gate the
toggle locally, with no extra RPC. `rated` is a **validated assertion**: the
client computes it from the twin plus its guest status and sends it; the edge
function recomputes `canBeRated = pool != null && !guest` and **rejects a
mismatch** (422) rather than coercing. There is no _forced-rated_ mode — only
forced-unrated (ineligible pool or guest) and toggle (eligible). Pool names are
server-authoritative; the client can never forge one.

---

## 9. Event Sourcing & Replayability

`game_states` is an **append-only history table**. One row is inserted per state
transition (including version 0 for the initial state), so the full game history
is always available at zero extra cost — no action log re-execution needed.

### Replay via the `game/replay` route

The `game/replay` route returns the caller's observation slice at every version.
The EF reads it as a single typed query — `game_states` with each row's
producing `action` **embedded** through the
`(game_id, version_after) → game_states` FK (the UNIQUE makes it a to-one) —
then applies the gate in TS:

```
game/replay { game_id }
  → games.select(…, game_states(…, actions(type, data, player_index)))  // FK embed
  → gate in TS: finished only + caller is a participant
  → for each game_states row (ordered by version):
       computeObservation(state, pending_players, player_index, …, is_replay=true)
  → [{version, data, pending_players, created_at,
      action_type, action_data, action_player_index}, …]
```

Each frame:

- `version` — 0-based state index (version 0 is the initial state)
- `data` — game-specific observation for the caller (output of
  `computeObservation`)
- `pending_players` — who was pending at this version (post-hook narrowing
  applied)
- `created_at` — when this state was committed
- `action_type` — `"user"` / `"system"` / `"bot"`; `null` for version 0 (no
  action produced it)
- `action_data` — raw action payload (e.g. `{"position": 4}`,
  `{"type":"timeout"}`, or `{"type":"forfeit","player_index":1}`); `null` for
  version 0
- `action_player_index` — 0-based seat of the **performer**, taken from the
  embedded action's `player_index` (denormalized at write time — survives user
  deletion). Set for user moves, bot moves, and a user resign; `null` for
  version 0 and for **every system action** (timeout, engine-driven forfeit),
  which has no performer. A timeout resolves the whole pending set at once, so
  the seats it _affected_ are derived from the `pending_players` diff between
  this frame and the previous one — not from `action_data`.

- Only finished games are replayable. The EF gate rejects
  `status != 'finished'`.
- The caller must be a participant. Non-participants (spectators) cannot replay.
- Raw state is **never** exposed — every version is projected through
  `computeObservation`. Post-game hidden-info reveal (e.g. a poker hand-history
  that still hides folded hands) is controlled entirely by the hook. If the hook
  reveals full state when `pending_players` is empty, the replay shows it; if it
  doesn't, the replay doesn't.
- The `actions` table remains an audit log. `version_after` on each action row
  links it to the `game_states` version it produced, enabling
  `WHERE version_after = N` joins for per-action inspection.

### What the action log gives you

- **Timeouts as actions**: the timeout commit inserts one identity-less system
  action (`type = 'system'`, all identity NULL, `data = {"type":"timeout"}`), so
  timeouts appear in the log alongside the resulting state row; the affected
  seats are read from the `pending_players` diff.
- **Resigns / forfeits as actions**: a user resign (`game/forfeit`) logs as a
  `user` action carrying the resigning seat (`data = {"type":"forfeit",...}`);
  an engine-driven forfeit (account-deletion purge) logs as an identity-less
  system action (`data.type = "auto_forfeit"`).
- **Correlation**: `actions.version_after` = `game_states.version` for the state
  snapshot the action produced — an enforced **FK + UNIQUE**, so the join is
  guaranteed 1:1 and embeddable. A JOIN on this column reconstructs "which
  action caused this state" for any audit or cheat-detection tool.

---

## 10. Security Model

- **Optimistic locking**: clients pass `expected_version`;
  `engine_commit_action` rejects stale versions. A forfeit commit deliberately
  has no version check — forfeiting is an unconditional intent, and the row lock
  alone keeps the action/state history ordered.
- **Row lock**: `FOR UPDATE` on `games` serializes all concurrent writers —
  every move, forfeit, and timeout commits through `engine_commit_action` for
  the same game. Because `game_states` is append-only (no single mutable row to
  lock), the lock migrated to `games`. `FOR UPDATE` acquires a row lock without
  writing, so no Realtime events fire on `games` during normal gameplay — only
  `finish_game()` writes to `games`, and that write was already there.
- **TOCTOU-free status check**: `engine_commit_action` merges the game-status
  check into the same `FOR UPDATE` read. There is no separate pre-lock status
  read that could race with a concurrent `finish_game`.
- **Deadline guard**: `engine_commit_action` rejects any action where
  `turn_deadline < NOW()` (checked after the lock).
- **`expire_all_turns` isolation**: the pg_cron sweep uses
  `DISTINCT ON (game_id) ORDER BY version DESC` to select only the latest
  deadline per game, ignoring stale deadlines in historical rows.
- **Deterrence audit**: if a client detects an illegal opponent action, it calls
  `flag_game`. An Edge Function replays the full action history; confirmed
  cheating triggers a ban and annuls the game.
- **Ratings audit**: an Edge Function validates the full action history before
  writing rating updates.

### RPC Security Pattern

Every client-callable RPC uses a single-layer `SECURITY DEFINER` pattern:

```sql
CREATE FUNCTION public.<fn>(…)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$ … $$;

REVOKE EXECUTE ON FUNCTION public.<fn>(…) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.<fn>(…) TO authenticated;
```

- The function lives in the `public` schema (accessible via PostgREST) with
  `SECURITY DEFINER` — it runs as the function owner (postgres), allowing writes
  to service-role-only tables (`game_states`, `actions`, `game_outcomes`,
  `auth.users`).
- `SET search_path = ''` on every function prevents search-path injection
  attacks.
- Permissions are explicit: `REVOKE EXECUTE FROM PUBLIC, anon` +
  `GRANT TO authenticated` — no implicit public access.
- Internal utility functions (`private.require_auth`, `private.get_participant`,
  `private.persist_transition`, etc.) remain in the `private` schema. They are
  called by the public `SECURITY DEFINER` functions and are never exposed via
  PostgREST.

> **History note**: An earlier version used a two-layer pattern — a thin
> `public.*` `SECURITY INVOKER` wrapper calling a `private.*` `SECURITY DEFINER`
> implementation. This was removed (commit `9c4c901`) because the wrapper added
> noise without a security benefit: both layers ran within the same Postgres
> session under the same elevated role.

---

## 11. Implementation Phases

### Phase 1 ✓ — Core Shell

Auth, dashboard, settings, `users`/`user_profiles` tables, Material 3 theming.

### Phase 2 ✓ — Networking & Infra

Full schema (`games`, `game_states`, `participants`, `observations`, `actions`,
`game_outcomes`), all RPC functions, PRNG, timing system, and a reference game
implementation.

Client features:

- Home screen with active games, "your turn" sorting, live `TurnCountdown` on
  cards, pull-to-refresh with staleness label.
- Lobby with paginated public games, per-game player count (embedded participant
  query), wait duration.
- Game screen with Realtime observation stream, pre-game waiting room
  (join/leave/cancel/start), in-game board, forfeit with confirmation dialog.
- History screen with paginated finished games and per-game outcome result.
- Client-side expiry trigger (the `game/expire` route) fired when the client
  detects `turn_deadline` has passed.
- Timing widget system: `TurnTimerBuilder`, `PlayerTimerBuilder` (headless
  builder widgets), `TurnCountdown`, `BudgetClock` (infra-owned styled shells),
  `TimingContext` passed to all `buildContent` calls.

### Phase 2.5 ✓ — Social & Friends

Friends system (`relationships` table, `friends_view`), friend routes on the
`social` function (`friend-request`, `accept`, `remove`), user search with
trigram indexes.

Game discovery:

- Short codes on games for invite-by-code joining (`app_join_game_by_code`).
- `friends` access enforcement in `app_join_game` (validates accepted friendship
  with creator).
- Friends lobby (`app_friends_games` RPC) with Public/Friends segmented toggle
  in lobby screen.
- Join-by-code flow: `/join/:code` route, `JoinGameScreen`, join code dialog on
  home screen.

Client features:

- Social screen with three tabs: Friends (accepted), Requests (incoming
  pending), Add Friend (search + send). Each tab uses
  `AutomaticKeepAliveClientMixin` so switching tabs does not re-fetch the list.
  Each list item is its own `ConsumerWidget` (`_FriendTile`, `_RequestTile`)
  that independently watches `playerInfoCacheProvider(id)` — only the affected
  tile rebuilds when a player's identity changes, not the whole list.
- Social navigation branch in shell scaffold.
- Pre-game waiting room displays short code for private/friends games.

### Phase 3 — Advanced Game Features

Additional games (Chess, Go, Literature, Poker, Exploding Kittens). Edge
Function validation for revelation actions. Push notifications for async games.

### Phase 4 ✓ — Rating & Bots

OpenSkill (Bayesian) rating system:

- `bots` table: bot player registry — identity plus the bot lifecycle
  (`is_local`, `schema_version`, `webhook_url`, `rated_eligible`, `config`).
  Local and server execution models, the per-bot HMAC auth (both directions),
  and one-identity-many-seats are covered in §26.
- `player_ratings` table: per-player per-pool mu/sigma/display_rating, upserted
  after each rated game.
- `rating_history` table: immutable per-game audit log with before/after
  snapshots.
- `ratingPool`: a game hook — the server derives the pool name from game config;
  clients cannot forge pool names. (See §8 for the rating pipeline.)
- `supabase/functions/_engine/ratings.ts`: OpenSkill computation (`openskill`,
  MIT) run **inside the commit** when a rated game finishes. Groups players by
  `team_index`, calls `rate(teams, {rank: placements})` on the rating inputs the
  commit already read, and hands the deltas to the finishing transaction. No
  separate function, no pg_net trigger, no webhook.
- `private.apply_rating_updates`: SECURITY DEFINER, service-role only. Called
  from `private.persist_transition` in the **same** finishing transaction —
  upserts `player_ratings` and inserts `rating_history` atomically. Idempotent
  via the unique `(game, identity)` indexes on `rating_history`.

Client:

- `PlayerInfo` is the unified identity model for both humans and bots — no
  separate BotInfo type. `app_players(uuid[])` RPC covers both via a UNION.
  `playerInfoCacheProvider(id)` works for any player UUID.
- `PlayerInfo` does not carry a rating field — detailed per-pool ratings are
  fetched separately via `myRatingsProvider` (own profile) or
  `playerRatingsProvider(id)` (other players' profiles / `PlayerProfileSheet`).
- `player_ratings` queryable directly via table RLS (no RPCs needed).
- `rating_history` embedded in `GameRepository.getHistoryGameEntries` alongside
  `game_outcomes` — not exposed as a standalone client query. Rating deltas
  (`▲ +N` / `▼ -N`) are shown inline on each history card.

---

## 12. File Structure

This is the **`eigen_engine` package** (its repo root). Paths in this document
written as `lib/core/...`, `lib/features/...`, `lib/shared/...` are relative to
it. An **app** that uses the engine adds it as a dependency and supplies a
`GameModule` plus its own `main.dart`, `env/`, `firebase_options.dart`, platform
folders and Supabase config — see `game_implementation_guide.md` for how a
consuming app is structured.

The engine also ships `bin/sync_supabase.dart` (the backend-vendoring CLI) and
the canonical backend under `supabase/` — `migrations/` (schema + RPCs),
`functions/` (edge functions), and `seed.sql` — alongside `lib/`.

```
lib/
├── eigen_engine.dart                 # Public barrel (runEngineApp, AppConfig, GameModule, …)
├── app_runner.dart                      # runEngineApp(...) entry point + root MyApp
├── core/
│   ├── config/
│   │   └── app_config.dart              # AppConfig (Branding + EngineConfig)
│   ├── game/
│   │   ├── game_creation_spec.dart       # GameCreationSpec, TimingModeConfig variants
│   │   ├── game_frame.dart               # GameFrame — per-event observation snapshot
│   │   ├── game_module.dart              # GameModule + GameRules contracts, GameContentContext, args twins
│   │   ├── game_outcome.dart             # GameOutcome, OutcomeResult
│   │   ├── game_player.dart              # GamePlayer — unified game-level player concept
│   │   ├── game_status.dart              # GameStatus enum
│   │   ├── players_context.dart          # PlayersContext — non-nullable player data for buildContent
│   │   └── timing_context.dart           # TimingContext — timing data passed to buildContent
│   ├── analytics/
│   │   ├── analytics_service.dart           # Abstract interface — identify, reset, event methods
│   │   ├── firebase_analytics_service.dart  # Firebase Analytics implementation
│   │   └── analytics_provider.dart          # analyticsServiceProvider (keepAlive: true)
│   ├── notifications/
│   │   ├── firebase_notification_service.dart  # FCM implementation
│   │   └── notification_provider.dart          # notificationServiceProvider (keepAlive: true)
│   ├── connectivity/
│   │   └── connectivity_provider.dart    # connectivityProvider (stream), isOfflineProvider (bool)
│   ├── storage/
│   │   ├── shared_preferences_provider.dart  # sharedPreferencesProvider (keepAlive: true)
│   │   ├── storage_provider.dart             # storageProvider (SQLite), profileCacheKey, deleteUserData
│   │   └── storage_provider.g.dart           # Generated
│   ├── updates/
│   │   └── update_notifier.dart          # UpdateNotifier — Play Store in-app update lifecycle
│   ├── review/
│   │   └── review_notifier.dart          # ReviewNotifier — in-app review, win-count gating
│   └── navigation/
│       ├── router/
│       │   └── app_router.dart           # GoRouter config — shell branches, game route (push semantics)
│       ├── utils/
│       │   └── stream_listenable.dart    # Bridges Stream<T> to GoRouter refreshListenable
│       ├── providers/
│       │   └── navigation_providers.dart # routerProvider (keepAlive) — GoRouter singleton with auth redirect
│       └── widgets/
│           └── shell_scaffold.dart        # NavigationDrawer — Home, Lobby, History, Social, About, Settings; _OfflineBanner; back exits app
├── shared/
│   ├── data/
│   │   ├── models/
│   │   │   └── player_info.dart          # PlayerInfo — unified identity for humans and bots (freezed)
│   │   └── player_repository.dart        # Fetches via app_players() RPC (unified humans + bots)
│   ├── providers/
│   │   └── player_providers.dart         # playerInfoCacheProvider(id) — keepAlive + @JsonPersist, humans and bots
│   └── widgets/
│       ├── empty_state_view.dart         # EmptyStateView — illustrated empty state for list screens
│       ├── player_avatar.dart            # PlayerAvatar — network image, person-icon fallback, optional border
│       ├── overlapping_avatars.dart      # OverlappingAvatars — for game cards
│       └── status_banner.dart            # StatusBanner — slim full-width system status banner
├── features/
│   ├── game/
│   │   ├── data/
│   │   │   ├── game_repository.dart      # All RPC calls + Realtime streams
│   │   │   └── models/
│   │   │       ├── game.dart             # Game (turnSeconds, budgetSeconds, shortCode, rated,
│   │   │       │                         #   ratingPool…)
│   │   │       ├── observation.dart      # Observation (data, pendingPlayers, turnDeadline,
│   │   │       │                         #   playerTimes, turnStartedAt)
│   │   │       └── participant.dart      # Participant (playerIndex, userId, botId, type)
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   ├── game_screen.dart      # Game screen state/dispatcher — pre-game, active,
│   │   │   │   │                         #   finished, aborted. Sub-widgets split into the
│   │   │   │   │                         #   game_screen_*.dart part files (pre_game/active/states)
│   │   │   │   ├── game_screen_pre_game.dart # `part of` game_screen.dart — waiting room + Add bot
│   │   │   │   ├── game_screen_active.dart   # `part of` game_screen.dart — active board + timing header
│   │   │   │   ├── game_screen_states.dart   # `part of` game_screen.dart — aborted/unsupported/error/banners
│   │   │   │   ├── history_screen.dart   # Paginated finished/aborted game history with inline rating deltas
│   │   │   │   ├── home_screen.dart      # Active games dashboard + join-by-code dialog
│   │   │   │   ├── join_game_screen.dart # Handles async join-by-code, redirects to game
│   │   │   │   └── lobby_screen.dart     # Public/Friends tabbed game browser (TabBar + AutomaticKeepAliveClientMixin)
│   │   │   └── widgets/
│   │   │       ├── budget_clock.dart     # Infra-owned N-player budget clock (stateless shell)
│   │   │       ├── timer_builders.dart   # TurnTimerBuilder, PlayerTimerBuilder (headless)
│   │   │       └── turn_countdown.dart   # Infra-owned per-action countdown (stateless shell)
│   │   └── providers/
│   │       ├── game_providers.dart       # gamePlayersProvider, activeGamesProvider, availableBots, soloPlayAvailable, etc.
│   │       ├── game_frame_provider.dart  # gameFrameProvider, gameRulesProvider, gameConfigProvider
│   │       └── local_bot_driver.dart     # LocalBotDriver supervisor + LocalBotSeatDriver — client-side solo local-bot driving (§26)
│   ├── profile/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── user_profile.dart         # UserProfile (freezed) — display_name, username, avatar_url
│   │   │   ├── avatar_storage_service.dart   # Uploads avatar to Supabase Storage, returns public URL
│   │   │   └── profile_repository.dart       # Reads/writes user_profiles; upserts via RPC
│   │   ├── presentation/
│   │   │   └── screens/
│   │   │       └── profile_screen.dart       # Cinematic SliverAppBar hero, rating cards, edit modal
│   │   └── providers/
│   │       └── profile_providers.dart        # currentUserProfileProvider (keepAlive, @JsonPersist, stale-while-revalidate)
│   ├── rating/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   ├── player_rating.dart    # PlayerRating — per-pool mu/sigma/displayRating (freezed)
│   │   │   │   └── rating_change.dart    # RatingChange — per-game history entry (freezed)
│   │   │   └── rating_repository.dart   # Queries player_ratings only; rating history is embedded in GameRepository
│   │   └── providers/
│   │       └── rating_providers.dart    # ratingRepositoryProvider, playerRatingsProvider(id), myRatingsProvider
│   └── social/
│       ├── data/
│       │   ├── models/
│       │   │   └── friendship.dart       # Friendship model (freezed) + RelationshipStatus enum
│       │   └── social_repository.dart    # Friend RPCs + app_search_users
│       ├── presentation/
│       │   ├── widgets/
│       │   │   ├── friend_actions.dart        # FriendActions widget — routes on FriendStatus, compact/full modes
│       │   │   ├── friend_buttons.dart        # SendRequestButton, AcceptButton, RemoveFriendButton, DeclineButton
│       │   │   └── player_profile_sheet.dart  # Profile bottom sheet — identity, ratings, social actions
│       │   └── social_screen.dart        # Tabbed social screen (Friends, Requests, Add Friend)
│       └── providers/
│           └── social_providers.dart     # Friendships (keepAlive, @JsonPersist, static Mutation fields: send/accept/remove);
│                                         # acceptedFriends, pendingRequests, sentRequests, friendStatus;
│                                         # FriendStatus enum, computeFriendStatus helper
```

A consuming app is a standard Flutter app with the game under `lib/game/`:

```
my_app/                                  # repo root (a standard Flutter app)
├── pubspec.yaml                         # depends on eigen_engine
├── lib/
│   ├── main.dart                        # ~30-line entry: runEngineApp(module, config, …)
│   ├── env/                             # Envied-generated env config (Env)
│   ├── firebase_options.dart
│   └── game/                            # the game
│       ├── game_module.dart             # MyGameModule (versions map + creation UI)
│       └── v1/                          # one folder per schema_version
│           ├── rules.dart               # MyGameRulesV1 (client GameRules unit)
│           ├── data/models/game_models.dart # ObservationData, ActionData, GameConfigData
│           └── presentation/{my_game_board,my_game_content}.dart
├── android/ ios/ web/ macos/ linux/ windows/
├── assets/                              # google_fonts, icons
└── supabase/                            # config.toml, functions, seed.sql, migrations/ (committed)
```

The engine's infra migrations are **vendored** into the app's committed
`supabase/migrations/` (alongside the app's game hook migration) by the
engine-owned CLI, run from the app: `dart run eigen_engine:sync_supabase`.

---

## 13. App Startup & Splash Screen

The native splash screen is kept visible until the auth state is known,
eliminating the GoRouter authentication redirect flash — the redirect from
`/home` → `/login` (or vice versa) happens behind the splash.

### Startup Sequence

```
OS launches process → OS shows native splash (static, instant)
  → main(): FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding)
    → Supabase.initialize() + font config
      → runApp(ProviderScope(child: AppStartup(child: MyApp())))
        → Flutter renders first frame (behind splash)
          → AppStartup.initState() awaits authStateChangesProvider.future
            → Supabase fires INITIAL_SESSION (~100–200 ms, from local session cache)
              → FlutterNativeSplash.remove()
                → splash animates away → user sees correct screen (home or login)
```

`authStateChangesProvider.future` resolves on the first Supabase stream emission
regardless of whether the user has a session — the splash never waits on a
network round-trip. No timeout is applied to this await: Supabase Flutter reads
the stored session from secure storage and emits `initialSession` locally, so
resolution is always fast. The sole exception is an **expired session with no
network** — the token-refresh attempt must time out before `signedOut` is
emitted. Supabase's own HTTP timeout handles this; enforcing a shorter app-level
timeout risks a flash to the login screen on a merely slow (not offline)
connection.

`currentUserProfileProvider.future` (awaited only when authenticated) is capped
at **2 seconds**. SQLite resolves in ~5 ms so the cap only fires on a first-ever
launch with no local cache and no network. In that case the `catch` block fires,
`FlutterNativeSplash.remove()` runs in `finally`, and the home screen opens with
the profile in a loading/shimmer state — no stuck splash.

### Dart Implementation

**`app_runner.dart`** (engine) — `runEngineApp` captures the binding before any
async work and passes it to `preserve()`, then initialises Firebase/Supabase and
runs the app. The app's `main.dart` just calls it:

```dart
// lib/app_runner.dart
Future<void> runEngineApp({...}) async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await Supabase.initialize(...);
  runApp(ProviderScope(overrides: [...], child: AppStartup(child: MyApp())));
}

// apps/my_app/lib/main.dart
Future<void> main() => runEngineApp(
  module: const MyGameModule(),
  config: AppConfig(branding: ..., engine: EngineConfig(...Env...)),
  firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  onBackgroundMessage: _firebaseMessagingBackgroundHandler,
);
```

**`lib/core/startup/app_startup.dart`** — `ConsumerStatefulWidget` that wraps
`MyApp`. Its `initState` awaits `authStateChangesProvider.future` and calls
`FlutterNativeSplash.remove()` in a `finally` block so the app is never stuck
behind the splash on error.

`flutter_native_splash` is a **runtime dependency** (not dev), required since
v2.0.0.

### `pubspec.yaml` Configuration

The `flutter_native_splash:` block is a top-level key — **not** nested under
`flutter:`:

```yaml
flutter_native_splash:
  color: "#FFFBFF" # Material 3 light surface (deepPurple seed)
  color_dark: "#141218" # Material 3 dark surface (deepPurple seed)
  image: assets/splash/logo.png # centered logo, 1152×1152 px
  image_dark: assets/splash/logo_dark.png # white/light version for dark background

  android_12: # covers Android 12, 13, 14, 15, 16+ (API 31+)
    color: "#FFFBFF"
    color_dark: "#141218"
    image: assets/splash/logo.png
    image_dark: assets/splash/logo_dark.png
    icon_background_color: "#FFFBFF"
    icon_background_color_dark: "#141218"

  web: false # set true to generate a web splash
```

Colors must stay in sync with the branding seed (`Branding.seedColor`, set in
`main.dart`). The native splash config can't read Dart, so if the seed color
changes, update both `color`/`color_dark` here and regenerate.

### Asset Requirements

Declare the folder in `pubspec.yaml` under `flutter: assets:` before adding
files:

```yaml
flutter:
  assets:
    - assets/splash/
```

**Required:**

| File                          | Size               | Notes                                                                                                                     |
| ----------------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `assets/splash/logo.png`      | **1152 × 1152 px** | Light-mode logo. Keep artwork within the inner **640 px** — the outer ring is cropped by Android 12's circular icon mask. |
| `assets/splash/logo_dark.png` | **1152 × 1152 px** | Dark-mode logo (white/light version for dark background).                                                                 |

The generator produces all Android density variants (mdpi → xxxhdpi) from these
single sources. Do not create per-density files manually.

**Optional — bottom branding (studio name, tagline):**

| File                              | Size          | Notes                                                               |
| --------------------------------- | ------------- | ------------------------------------------------------------------- |
| `assets/splash/branding.png`      | ≥ 600 px wide | Add `branding:` and `branding_bottom_padding:` to the config block. |
| `assets/splash/branding_dark.png` | ≥ 600 px wide | Dark variant.                                                       |

### Regenerating Platform Files

Run after any change to the `flutter_native_splash:` config block or splash
image assets:

```bash
dart run flutter_native_splash:create
```

**Generated files — do not edit manually:**

| File(s)                                                             | Applies to                                   |
| ------------------------------------------------------------------- | -------------------------------------------- |
| `android/.../drawable*/launch_background.xml` + `background.png`    | Pre-Android 12 (all densities)               |
| `android/.../values/styles.xml` + `values-night/styles.xml`         | Android ≤ 11 — `windowBackground` drawable   |
| `android/.../values-v31/styles.xml` + `values-night-v31/styles.xml` | Android 12+ — `windowSplashScreenBackground` |
| `ios/Runner/Info.plist`                                             | iOS status bar configuration                 |

### Android API Boundary

`-v31` is a **minimum-version qualifier**, not an exact match. The `android_12:`
config block covers every Android release from API 31 onwards:

| Resource folder | Android version               | Mechanism                                         |
| --------------- | ----------------------------- | ------------------------------------------------- |
| `values/`       | ≤ 11 (API ≤ 30)               | `android:windowBackground` drawable               |
| `values-v31/`   | 12, 13, 14, 15, 16… (API 31+) | `windowSplashScreenBackground` (SplashScreen API) |

The system picks the highest-matching qualifier at runtime. "Android 12" in the
config name refers to when the SplashScreen API was introduced, not a version
ceiling.

---

## 14. Observability & Analytics

Analytics and crash reporting are **infra-owned** — game implementors do not add
Firebase calls. All events fire automatically from core infrastructure.

### Packages

| Package                | Purpose                                        |
| ---------------------- | ---------------------------------------------- |
| `firebase_analytics`   | Event tracking, user identity, screen tracking |
| `firebase_crashlytics` | Fatal/non-fatal crash capture                  |

Firebase is **mandatory** — initialized unconditionally in `main()` alongside
Supabase. Every deployment runs it.

### Architecture

```
lib/core/analytics/
├── analytics_service.dart           # Abstract interface — primitives only, no features/ imports
├── firebase_analytics_service.dart  # Firebase implementation
└── analytics_provider.dart          # analyticsServiceProvider (keepAlive: true)
```

`AnalyticsService` uses primitive types (`String`, `int`, `bool`) in all method
signatures and never imports `features/` types. Call sites convert enums to
strings (e.g., `_access.name`).

The provider returns a `FirebaseAnalyticsService` backed by
`FirebaseAnalytics.instance`. The abstract interface keeps call sites decoupled
from Firebase and makes the service straightforward to fake in tests.

### Initialization

`main.dart` initializes Firebase before Supabase, then wires Crashlytics:

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
PlatformDispatcher.instance.onError = (error, stack) {
  FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  return true;
};
```

`FlutterError.onError` catches framework-level errors (widget build failures,
assertion errors). `PlatformDispatcher.instance.onError` catches isolate-level
errors that escape the framework. Both are wired before `runApp` so no crash
window exists at startup.

`firebase_options.dart` is generated once by `flutterfire configure` — do not
hand-edit it.

### Identity Lifecycle

`lib/core/startup/app_startup.dart` wires identity to the Supabase auth stream:

```dart
void _onAuthStateChange(
  AsyncValue<AuthState>? _,
  AsyncValue<AuthState> next,
) {
  next.whenOrNull(
    data: (authState) {
      final analytics = ref.read(analyticsServiceProvider);
      switch (authState.event) {
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.signedIn:
          if (authState.session?.user.id case final id?) {
            unawaited(analytics.identify(id));
            // Fire-and-forget: starts the SQLite cache restore + network
            // fetch before any screen renders. keepAlive ensures the result
            // is reused by all subsequent watchers.
            ref.read(currentUserProfileProvider.future).ignore();
          }
        case AuthChangeEvent.signedOut:
          unawaited(analytics.reset());
        default:
          break;
      }
    },
  );
}
```

Both `initialSession` and `signedIn` call `identify()` — without both, returning
users (cold start with an existing session) would never be identified because
Supabase fires `initialSession`, not `signedIn`, on startup.

`ref.read(currentUserProfileProvider.future).ignore()` starts the
stale-while-revalidate cycle (SQLite cache restore + background network fetch)
while the splash is still animating away. Because `currentUserProfileProvider`
is `keepAlive: true`, the result is shared with all future watchers — no
redundant fetch occurs when the Profile screen first opens. See §23 for the full
persistence design.

`identify` maps to `FirebaseAnalytics.setUserId`; `reset` clears it with
`setUserId(id: null)`.

### Screen Tracking

`FirebaseAnalyticsObserver` is registered on the GoRouter instance in
`navigation_providers.dart`:

```dart
observers: [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
```

This automatically records a `screen_view` event on every route transition.

### Events

| Event               | Firebase name         | Properties                                            | Source                                                                   |
| ------------------- | --------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------ |
| `gameCreated`       | `game_created`        | `game_id`, `access`, `timing_mode`, `rated` (int 0/1) | `new_game_dialog.dart` after `createGame()` succeeds                     |
| `gameStarted`       | `game_started`        | `game_id`, `player_count`                             | `game_screen.dart` when game transitions to `active`                     |
| `gameFinished`      | `game_finished`       | `game_id`                                             | `game_screen.dart` when outcomes first arrive (non-empty)                |
| `forfeit`           | `forfeit`             | —                                                     | `game_screen.dart` after the `game/forfeit` route succeeds               |
| `joinByCode`        | `join_by_code`        | —                                                     | `join_game_screen.dart` after `app_join_game_by_code` RPC succeeds       |
| `friendRequestSent` | `friend_request_sent` | —                                                     | `social_providers.dart` after the `social/friend-request` route succeeds |
| `friendAccepted`    | `friend_accepted`     | —                                                     | `social_providers.dart` after the `social/accept` route succeeds         |

**Note:** Firebase Analytics does not accept raw `bool` parameters. `rated` is
sent as `int` (0 or 1).

### `game_started` and `game_finished` implementation

Both use `ref.listenManual` in `game_screen.dart`'s `initState`, not
`ref.listen` in `build`. This is the correct Riverpod pattern for side effects
that must not re-fire on widget rebuilds.

**`game_started`** fires only on a _witnessed_ pre-game → active transition:
`prev?.value?.status` must be `waiting` or `ready`. On the first emission after
mounting, `prev?.value` is null, so opening an already-active game does not
re-count the start. The player count is read via
`ref.read(gamePlayersProvider(...))` before the handler invalidates that
provider, so the count is still available at fire time:

```dart
void _onGameStatusChange(AsyncValue<Game>? prev, AsyncValue<Game> next) {
  final prevStatus = prev?.value?.status;
  final status = next.value?.status;
  if (prevStatus == status) return;
  if (status == GameStatus.active &&
      (prevStatus == GameStatus.waiting || prevStatus == GameStatus.ready)) {
    final count = ref
        .read(gamePlayersProvider(gameId: widget.gameId))
        .value
        ?.players
        .length ?? 0;
    ref.read(analyticsServiceProvider).gameStarted(
      gameId: widget.gameId,
      playerCount: count,
    );
  }
  // …provider invalidation follows…
}
```

**`game_finished`** fires only on a witnessed empty → non-empty outcomes
transition, guarded by `prev?.value?.isEmpty != true`. This covers both re-fire
paths: on first load (re-opening a finished game from History) `prev?.value` is
null; on app-resume reloads `AsyncLoading` in Riverpod 3.x carries the previous
non-empty `value`. In both cases the guard returns early:

```dart
void _onGameOutcomes(
  AsyncValue<List<GameOutcome>>? prev,
  AsyncValue<List<GameOutcome>> next,
) {
  if (prev?.value?.isEmpty != true) return;
  if (next.value?.isEmpty ?? true) return;
  ref.read(analyticsServiceProvider).gameFinished(gameId: widget.gameId);
}
```

### Setup (per deployment)

1. Create a Firebase project at console.firebase.google.com — use the
   **Flutter** app type to register Android and iOS in one flow. Enable
   **Analytics** and **Crashlytics**.
2. `npm install -g firebase-tools && firebase login`
3. `dart pub global activate flutterfire_cli`
4. From the project root: `flutterfire configure` — select **Android** and
   **iOS** only. This generates `lib/firebase_options.dart`,
   `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`,
   and `firebase.json`. All four are gitignored (instance-specific, not engine
   artifacts) and must never be committed.
5. Re-run `dart run build_runner build`.

### CI secrets (GitHub Actions)

The gitignored files must be supplied to CI as base64-encoded secrets. Encode
locally and add to repo Settings → Secrets → Actions:

```bash
base64 -i lib/firebase_options.dart        | pbcopy  # → FIREBASE_OPTIONS_DART_BASE64
base64 -i android/app/google-services.json | pbcopy  # → GOOGLE_SERVICES_JSON_BASE64
# iOS (when iOS CI workflow is added):
base64 -i ios/Runner/GoogleService-Info.plist | pbcopy  # → GOOGLE_SERVICE_INFO_PLIST_BASE64
```

`firebase.json` is only used by the `flutterfire` CLI to know which project/app
IDs to target on the next `flutterfire configure` run. It is not read during
`flutter build appbundle` and does **not** need to be a CI secret.

The Android workflow decodes secrets before the build:

```yaml
- name: Decode Firebase config
  run: |
    echo "${{ secrets.FIREBASE_OPTIONS_DART_BASE64 }}" | base64 --decode > lib/firebase_options.dart
    echo "${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}" | base64 --decode > android/app/google-services.json
```

`firebase_options.dart` is also decoded in the `test` job (only this file — no
`google-services.json` needed there) so `flutter analyze` can resolve the
import.

With `google-services.json` present, the `firebase-crashlytics-gradle` plugin
automatically uploads R8/ProGuard mapping during `flutter build appbundle`. Dart
deobfuscation symbols (`--split-debug-info` output) are uploaded as a GitHub
Actions artifact and may require an additional Gradle task — see §18.

### Files

| File                                                      | Role                                                                   |
| --------------------------------------------------------- | ---------------------------------------------------------------------- |
| `lib/firebase_options.dart`                               | Generated by `flutterfire configure` — gitignored, not hand-maintained |
| `android/app/google-services.json`                        | Android native Firebase config — gitignored                            |
| `ios/Runner/GoogleService-Info.plist`                     | iOS native Firebase config — gitignored                                |
| `firebase.json`                                           | FlutterFire CLI project metadata — gitignored, not needed in CI        |
| `lib/main.dart`                                           | Firebase init + Crashlytics wiring                                     |
| `lib/core/analytics/analytics_service.dart`               | Abstract interface                                                     |
| `lib/core/analytics/firebase_analytics_service.dart`      | Firebase implementation                                                |
| `lib/core/analytics/analytics_provider.dart`              | `analyticsServiceProvider` (keepAlive)                                 |
| `lib/core/navigation/providers/navigation_providers.dart` | `FirebaseAnalyticsObserver` on GoRouter                                |

---

## 15. Store Integration

### In-App Updates (Android)

Implemented via [`in_app_update`](https://pub.dev/packages/in_app_update), which
wraps the Play Core `AppUpdateManager`. The Play Core SDK is an OS-managed
singleton — concurrent calls to `checkForUpdate()` are handled natively and do
not require an application-level concurrency guard.

#### Architecture

```
AppStartup.AppLifecycleListener.onResume
        ↓
UpdateNotifier.checkForUpdate()          (keepAlive Riverpod notifier)
        ↓
InAppUpdate.checkForUpdate()             (Play Core query)
        ├─ previouslyDownloaded?  →  state = downloadComplete
        ├─ immediateUpdateAllowed?
        │   ├─ not in-game  →  performImmediateUpdate()   (full-screen system UI)
        │   └─ in-game      →  skip; retry on next resume
        └─ flexibleUpdateAllowed? →  startFlexibleUpdate()
                                      → state = downloadComplete on success
                                              ↓
                                    ShellScaffold ref.listen
                                      → SnackBar "A new version is ready." + Restart action
                                              ↓
                                    UpdateNotifier.completeUpdate()
                                      → completeFlexibleUpdate() → app restarts
```

#### Key decisions

**Immediate vs flexible branching** — when `immediateUpdateAllowed` is `true`,
the immediate path owns that branch entirely. If a game is active the method
returns without starting a flexible update — an immediate update is never
silently downgraded. The next `onResume` will retry.

**Mid-game gate** — `UpdateNotifier._isGameActive()` reads the current URI from
`goRouterProvider.routerDelegate.currentConfiguration.uri`. Game routes live
under `/game/`, which sits outside the shell navigator (root
`parentNavigatorKey`), so the prefix check is reliable. No extra state is
needed.

**Previously-downloaded updates** — a flexible update downloaded in a prior
session surfaces via
`UpdateAvailability.developerTriggeredUpdateInProgress + InstallStatus.downloaded`.
This is checked first on every resume so the user is never left waiting for a
redundant re-download.

**Snackbar placement** — `AppStartup` sits above `MaterialApp` and cannot
resolve `ScaffoldMessenger`. `UpdateNotifier` exposes state instead;
`ShellScaffold` (which has scaffold context) reacts via `ref.listen` and shows
the snackbar. This keeps all UI in the widget tree and all lifecycle logic in
the notifier.

#### Files

| File                                              | Role                                                               |
| ------------------------------------------------- | ------------------------------------------------------------------ |
| `lib/core/updates/update_notifier.dart`           | `UpdateNotifier` notifier + `UpdateInstallStatus` enum             |
| `lib/core/startup/app_startup.dart`               | `AppLifecycleListener` wiring — calls `checkForUpdate()` on resume |
| `lib/core/navigation/widgets/shell_scaffold.dart` | `ref.listen(updateProvider, …)` → snackbar                         |

#### Packages

```yaml
dependencies:
  in_app_update: ^4.x.x # wraps Play Core AppUpdateManager
```

iOS has no equivalent — `checkForUpdate()` returns early if
`!Platform.isAndroid`.

---

### In-App Review

Implemented via [`in_app_review`](https://pub.dev/packages/in_app_review). The
OS silently enforces its own quota (3× per year on both platforms) — no
application-level gate beyond the modulo trigger is needed or appropriate.

#### Architecture

```
GameScreen._onGameOutcomes()
        ↓  (only when outcomes first arrive, not on resume reload)
ReviewNotifier.onWin()               (keepAlive AsyncNotifier)
        ↓
SharedPreferences total_wins++       (persisted across sessions)
        ↓  count % 5 == 0?
InAppReview.isAvailable() → requestReview()
```

#### Key decisions

**Win counting** — all wins count regardless of game type, timing mode, or rated
status. The `OutcomeResult.win` check is the only gate applied at the call site
in `GameScreen`.

**Trigger frequency** — a review prompt is requested every `_reviewEveryNWins`
(5) wins. The OS may silently no-op the request if its own quota is exhausted;
the counter keeps incrementing regardless so the next qualifying win will retry.

**Persistence** — `ReviewNotifier` uses `sharedPreferencesProvider` (a shared
keepAlive provider in `lib/core/storage/shared_preferences_provider.dart`) so
the same `SharedPreferences` instance is used across all consumers without
duplicate initialization.

**Fire-and-forget** — `GameScreen` calls `onWin()` via `unawaited()` so a slow
Play Store / App Store round-trip never delays the outcome UI.

**Deduplication** — `_onGameOutcomes` in `GameScreen` guards with
`if (prev?.value?.isEmpty != true) return` (the same guard used for analytics):
the win only counts on a witnessed empty → non-empty outcomes transition.
Re-opening a finished game (`prev?.value` null on first load) and app-resume
reloads (`AsyncLoading` carries the previous non-empty value in Riverpod 3.x)
both return early, so revisiting an old win never inflates the review counter.

#### Files

| File                                                      | Role                                                                               |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `lib/core/review/review_notifier.dart`                    | `ReviewNotifier` — win counter + review request                                    |
| `lib/core/storage/shared_preferences_provider.dart`       | `sharedPreferencesProvider` — shared across `ReviewNotifier` and `ThemeController` |
| `lib/features/game/presentation/screens/game_screen.dart` | `_onGameOutcomes` → `unawaited(ref.read(reviewProvider.notifier).onWin())`         |

#### Packages

```yaml
dependencies:
  in_app_review: ^2.x.x
```

The review dialog **never appears on simulators or debug builds** — always test
on a real device through TestFlight or the Play Store internal track.

---

## 16. Haptic Feedback

Haptic feedback is **infra-owned** — game implementors do not import
`flutter/services.dart` or choose which haptic to fire. All three feedback
moments are wired automatically from `game_screen.dart`.

No package is required; `HapticFeedback` ships with `flutter/services.dart`.

### Feedback Moments

| Moment                 | Haptic           | Source                                                                                                   |
| ---------------------- | ---------------- | -------------------------------------------------------------------------------------------------------- |
| Valid action submitted | `lightImpact`    | `_GameScreenState._submitAction` — fires before the RPC call (optimistic)                                |
| Win outcome arrives    | `heavyImpact`    | `_GameScreenState._maybeTriggerWinHaptic` — called from `_onGameOutcomes` alongside analytics and review |
| Invalid move attempted | `selectionClick` | `onInvalidAction` callback, wired by `_ActiveGameContent` and called by the game content widget          |

### `onInvalidAction` Contract

`GameRules.buildContent()` receives an `onInvalidAction: VoidCallback`
parameter provided by infra. Game content widgets call it whenever
`GameRules.isValidAction` returns false on a player-initiated tap. Infra wires
it to `HapticFeedback.selectionClick()`; game implementors do not choose the
haptic.

```dart
onCellTap: (position) {
  final action = ActionData(position: position);
  final legal = rules.isValidAction(
    obs: observation,
    pending: pendingPlayers,
    data: action,
    playerIndex: myPlayerIndex,
    config: config,
  );
  if (legal) {
    onAction(rules.serializeAction(action));
  } else {
    onInvalidAction(); // infra fires selectionClick
  }
},
```

### Deduplication

`_maybeTriggerWinHaptic` is called from `_onGameOutcomes`, which is guarded by
`if (prev?.value?.isEmpty != true) return`. This is the same guard used for
analytics and in-app review: the haptic fires only on a witnessed empty →
non-empty outcomes transition, never when re-opening a finished game or when
`gameOutcomesProvider` reloads on app resume.

### Files

| File                                                                   | Role                                                                                                                                          |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/game/presentation/screens/game_screen.dart`              | `_submitAction` → `lightImpact`; `_maybeTriggerWinHaptic` → `heavyImpact`; `_ActiveGameContent` → wires `onInvalidAction` to `selectionClick` |
| `lib/core/game/game_module.dart`                                       | `buildContent` contract — declares `onInvalidAction: VoidCallback`                                                                            |
| the game package's content widget (`presentation/<game>_content.dart`) | Calls `onInvalidAction()` in the rejection branch                                                                                             |

---

## §17 Navigation

### Route Hierarchy

```
/ (root Navigator)
├── /home       ─┐
├── /lobby       │  StatefulShellRoute.indexedStack — shell branches
├── /history     │  (sibling widgets, not Navigator stack entries)
├── /social      │
├── /about       │
└── /settings   ─┘
/game/:gameId        parentNavigatorKey: rootNavigatorKey — covers shell entirely
/join/:code          parentNavigatorKey: rootNavigatorKey — transient join spinner
/profile             parentNavigatorKey: rootNavigatorKey
```

`/game`, `/join`, and `/profile` are declared with
`parentNavigatorKey: rootNavigatorKey` so they render above the shell scaffold
on the root navigator, not inside a branch.

### Navigation Method Semantics

| Method                          | Replaces stack?             | Back behavior                  | When to use                                  |
| ------------------------------- | --------------------------- | ------------------------------ | -------------------------------------------- |
| `context.go(path)`              | Yes — replaces entire stack | Exits app or lands at new root | Auth redirects, sign-out, branch switching   |
| `context.push(path)`            | No — adds to stack          | Returns to previous screen     | Any screen the user expects Back to undo     |
| `context.pushReplacement(path)` | Replaces current entry only | Returns to entry below current | Transient screens (e.g. join spinner → game) |

### Back Behavior by Route

**Shell branches (Home, Lobby, History, Social, About, Settings):** Each branch
is a top-level destination. There is no `PopScope` intercepting back. Pressing
Back from any branch exits the app with the system's predictive exit animation.
Users switch branches via the drawer — Back is not a navigation gesture between
branches.

**Game screen:** Always reached via `context.pushNamed('game', ...)`. Back
returns the user to whichever screen they came from (home, lobby, history). The
predictive back gesture shows a peek of the source screen.

**Join screen (`/join/:code`):** On success:
`context.pushReplacementNamed('game', ...)` — atomically replaces the join
spinner with the game screen so back from game does not land on a stuck spinner.
On error: `context.goNamed('home')` — safe fallback that works for both in-app
entry and deep-link cold start (where no shell is in the stack).

**In-app join flow (from home dialog):** `context.pushNamed('join', ...)` pushes
the join screen. The join screen then `pushReplacementNamed` the game screen.
Final stack: `[shell/home → game]`. Back from game → home.

### Predictive Back Gesture (Android 14+)

The activity declares `android:enableOnBackInvokedCallback="true"` in
`AndroidManifest.xml`. This opts the app into the Android 14+ predictive back
API.

GoRouter 17.x handles the back animation automatically:

- **Push routes** (game, join, profile): back shows a peek of the underlying
  route — correct behavior, no extra code needed.
- **Shell branches**: no route is beneath the branch on the navigator, so
  Android shows the standard exit-app animation — also correct for top-level
  destinations.

Do not remove `android:enableOnBackInvokedCallback="true"` from the manifest.
Its absence silently disables predictive back for all users on Android 14+.

### Auth Redirect Pattern

The GoRouter `redirect` callback watches `authStateProvider`. When the auth
state changes (sign-in or sign-out), `StreamListenable` notifies the router,
which re-evaluates the redirect and navigates accordingly.

`routerProvider` is `keepAlive: true` so the GoRouter instance persists for the
app lifetime and is never disposed between navigations.

### Unmatched Route Safety Net

`GoRouter` is configured with an `onException` handler that redirects any
unmatched or malformed route to `/home`:

```dart
GoRouter(
  onException: (_, state, router) => router.go('/home'),
  …
)
```

This handles iOS Universal Links that the OS hands to the app but whose path
does not match any declared route (e.g. a `/terms` deep-link intercepted by
Universal Links that has no GoRouter route). Without this handler, GoRouter
throws a `GoException` that surfaces as an unhandled exception crash.

### Notification-Triggered Navigation

Push notification taps emit a deep-link path from
`NotificationService.navigationStream`. `AppStartup` routes these via the
`NotificationNavigation` extension on `GoRouter` (defined in `app_router.dart`):

```dart
extension NotificationNavigation on GoRouter {
  static const _overlayPrefixes = ['/game/', '/join/'];

  void navigateFromNotification(String path) {
    if (_overlayPrefixes.any(path.startsWith)) {
      push(path);   // overlay routes — back returns to previous screen
    } else {
      go(path);     // shell tab routes — switches tab, no back entry
    }
  }
}
```

The distinction mirrors the route structure: `/game/` and `/join/` use
`parentNavigatorKey: rootNavigatorKey` (overlay routes) and must be pushed so
the system back button returns the user to where they were. Shell tab routes
(`/social`, `/lobby`, etc.) use `go` to switch tabs cleanly. When a new
overlay-prefix route is added, add it to `_overlayPrefixes`.

### Files

| File                                                      | Role                                                                     |
| --------------------------------------------------------- | ------------------------------------------------------------------------ |
| `lib/core/navigation/router/app_router.dart`              | GoRouter config, `NotificationNavigation` extension                      |
| `lib/core/navigation/utils/stream_listenable.dart`        | Bridges `Stream<T>` to `ChangeNotifier` for GoRouter `refreshListenable` |
| `lib/core/navigation/providers/navigation_providers.dart` | `routerProvider` — GoRouter singleton (`keepAlive: true`)                |
| `lib/core/navigation/widgets/shell_scaffold.dart`         | `NavigationDrawer` shell — no `PopScope`; back exits app                 |
| `android/app/src/main/AndroidManifest.xml`                | `android:enableOnBackInvokedCallback="true"` opts into predictive back   |

---

## 18. Android Release Hardening

Two complementary mechanisms harden the Android release build: R8 code shrinking
at the Java/Kotlin layer and Dart-level obfuscation at the native binary layer.
They are independent and both should be enabled.

### R8 Code Shrinking

R8 (the successor to ProGuard, default since Android Gradle Plugin 7.0) is
enabled in `android/app/build.gradle.kts`:

```kotlin
buildTypes {
    release {
        isMinifyEnabled = true      // activates R8 shrinking + obfuscation
        isShrinkResources = true    // removes unused Android resources
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro",
        )
    }
}
```

`isShrinkResources` requires `isMinifyEnabled`. Together they reduce APK size
and obfuscate the Java/Kotlin bytecode layer.

### ProGuard Rules (`android/app/proguard-rules.pro`)

Only libraries that do not ship their own consumer rules need explicit entries.
Libraries that handle their own rules automatically (via `consumerProguardFiles`
in their Maven artifacts or plugin build files) are intentionally omitted:

| Library                           | Why omitted                                                               |
| --------------------------------- | ------------------------------------------------------------------------- |
| Flutter engine                    | Rules added automatically by the Flutter Gradle plugin                    |
| `image_cropper`                   | Ships `consumer-proguard-rules.pro` (OkHttp + uCrop)                      |
| `google_sign_in` 7.x              | Credential Manager + Play Services Maven artifacts include consumer rules |
| `in_app_update` / `in_app_review` | Google Play Core Maven artifacts include consumer rules                   |
| `supabase_flutter`                | Pure Dart — no Android Java/Kotlin classes exist to protect               |

Libraries with explicit rules:

```proguard
# Supabase: conservative keep in case a future version adds a native Android layer.
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**
```

### Dart Obfuscation

`--obfuscate` renames Dart symbols (class/method names → `a`, `b`, …) in the
compiled native binary. `--split-debug-info` writes the mapping file to a
separate directory so crash stack traces can be deobfuscated by Sentry or
Crashlytics.

These are Flutter tool flags — they belong in the CI release build command, not
in Gradle:

```bash
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/debug-info/android/

flutter build ipa --release \
  --obfuscate \
  --split-debug-info=build/debug-info/ios/
```

The `build/debug-info/` output is excluded from git via the existing `/build/`
entry in `.gitignore`.

The Android CI workflow builds with these flags and handles symbol upload in two
ways:

- **R8/ProGuard mapping** — uploaded automatically by the
  `firebase-crashlytics-gradle` plugin during the build, as long as
  `google-services.json` is present (decoded from `GOOGLE_SERVICES_JSON_BASE64`
  secret before the build).
- **Dart deobfuscation symbols** — uploaded as a GitHub Actions artifact. An
  explicit `uploadCrashlyticsSymbolFileRelease` Gradle task step is commented
  out in the workflow; enable it if Dart symbols do not appear automatically in
  the Firebase Crashlytics dashboard after the first build.

The iOS workflow (when added) mirrors this pattern with
`--split-debug-info=build/debug-info/ios/` and
`GOOGLE_SERVICE_INFO_PLIST_BASE64`.

---

## 19. Connectivity & Offline Handling

Connectivity detection is **infra-owned** — game implementors do not watch
`connectivityProvider` or `isOfflineProvider` directly. All offline UI fires
automatically from core infrastructure.

### Providers (`lib/core/connectivity/connectivity_provider.dart`)

| Provider               | Type                               | Description                                                                                                                                                                                            |
| ---------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `connectivityProvider` | `Stream<List<ConnectivityResult>>` | Raw stream from `connectivity_plus`. Emits on every network interface change.                                                                                                                          |
| `isOfflineProvider`    | `bool`                             | `true` when every result in the latest emission is `ConnectivityResult.none`. Returns `false` during the brief loading window before the first event so the UI never flash-shows "offline" on startup. |

**Caveat:** `connectivity_plus` reflects network interface availability (Wi-Fi
associated, cell registered), not actual internet reachability. A device
connected to a Wi-Fi router with no upstream internet will report online.

### Offline Banners

Two distinct banners use `StatusBanner` (`shared/widgets/status_banner.dart`) —
a full-width slim container that sits outside `SafeArea` and bleeds
edge-to-edge:

| Banner                | Location        | Condition                                                                                                                       | Content                                                                             |
| --------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `_OfflineBanner`      | `ShellScaffold` | `isOfflineProvider == true` (any shell screen)                                                                                  | `wifi_off_rounded` icon + "No internet connection" — `errorContainer` colour scheme |
| `_ReconnectingBanner` | `GameScreen`    | `(isOffline \|\| obsAsync is AsyncError \|\| gameAsync is AsyncError)` **and** game is non-terminal (waiting, ready, or active) | Spinner + "Reconnecting…" — `secondaryContainer` colour scheme                      |

Both banners are wrapped in `AnimatedSize` (200 ms, `Curves.easeInOut`). The
layout pushes content down rather than overlaying it — nothing is obscured — but
the height transition is animated so the layout shift is a smooth slide rather
than an instant jump.

The game screen uses `_ReconnectingBannerSlot` (a `ConsumerWidget` leaf) to
isolate connectivity rebuilds — when the connection drops or recovers, only the
banner slot rebuilds, not the entire `_GameScreenState` tree.

`_ReconnectingBannerSlot` watches three sources: `isOfflineProvider`,
`gameObservationProvider`, and `gameStreamProvider`. The
`gameAsync is AsyncError` arm covers transient Supabase blips where the
WebSocket drops but the device never goes fully offline — `isOfflineProvider`
stays false, yet the stream has errored. `AsyncValue.value` is used to read the
stale game status during error states (when `gameAsync` is `AsyncError`, the
last-known `Game` is still accessible via `.value`) so the banner is never shown
after a game ends.

### Network Error Humanization

`humanize()` (`lib/core/errors/error_messages.dart`) maps raw exceptions to
user-friendly strings for snackbars. Network-failure errors are matched by
`_isNetworkError()`, which checks for common patterns across platforms
(`SocketException`, `Failed host lookup`, `Network request failed`,
`Connection refused`, `XMLHttpRequest error`, `network_error`,
`Unable to connect`) and returns
`"Can't reach the server. Check your connection."`.

The login screen's `GoogleSignInButton` passes sign-in errors through
`humanize()` so network failures produce the friendly string rather than a raw
exception. All in-game action errors already used `humanize()` — the login
screen is now consistent with that pattern.

### Realtime Channel Implementation

`GameRepository._channelStream<T>` is the shared helper that backs both
`gameStream()` and `observationStream()`. It uses Supabase's lower-level channel
API — `supabase.channel()` + `onPostgresChanges()` + `subscribe(callback)` —
rather than the `.stream()` convenience method.

The key difference: `.stream()` closes its `StreamController` on
`RealtimeSubscribeStatus.closed` (a plain WebSocket drop). Riverpod sees a
completed stream, holds the last `AsyncData`, and never retries.
`_channelStream` keeps the `StreamController` open across `closed`, trusting
Supabase's auto-reconnect to fire `subscribed` again and calling
`fetchCurrent()` at that point to guarantee fresh state.

**Status handling:**

| Status                      | Action                                                                                |
| --------------------------- | ------------------------------------------------------------------------------------- |
| `subscribed`                | `fetchCurrent()` via REST — initial load and every reconnect                          |
| `channelError` / `timedOut` | `controller.addError(…)` — Riverpod catches this and retries with exponential backoff |
| `closed`                    | No-op — Supabase auto-reconnects; next `subscribed` fires `fetchCurrent()`            |

**`channel.unsubscribe()` vs `removeChannel()`:** `onCancel` calls
`channel.unsubscribe()`, not `_client.removeChannel(channel)`. `removeChannel`
contains a race-prone `if (channels.isEmpty) disconnect()` check — when two
providers are simultaneously invalidated, both `removeChannel` calls may
complete before new channels are added, momentarily emptying the list and
disconnecting the WebSocket. `unsubscribe()` sends a leave push and the channel
removes itself from `client.channels` via its own
`_onClose → socket.remove(this)` callback, with no socket-level disconnect
side-effect. This is the same cleanup path Supabase's own `.stream()` used
internally.

**Riverpod retry:** Both `gameStreamProvider` and `gameObservationProvider` use
a plain `@riverpod` annotation — no custom retry function. Riverpod 3.x
`ProviderContainer.defaultRetry` applies: exponential backoff from 200 ms up to
6400 ms, up to 10 retries, for any `Exception` type (`Error` and
`ProviderException` are not retried). Channel errors (`channelError`,
`timedOut`) are all `Exception` types, so retry triggers automatically on every
Realtime failure.

### Auto-Reconnect (`_onConnectivityChange`)

`GameScreen` registers a
`ref.listenManual(isOfflineProvider, _onConnectivityChange)` listener in
`initState`. On the offline → online transition it immediately invalidates both
stream providers, bypassing Riverpod's retry backoff for the fast offline→online
path:

```dart
void _onConnectivityChange(bool? wasOffline, bool isOffline) {
  if (wasOffline != true || isOffline) return;
  // Invalidate both streams immediately, bypassing Riverpod retry backoff.
  ref.invalidate(gameStreamProvider(gameId: widget.gameId));
  ref.invalidate(gameObservationProvider(gameId: widget.gameId));
  if (_pendingExpiry) {
    _pendingExpiry = false;
    unawaited(_triggerExpiry());
  }
}
```

Invalidating resets the retry counter and forces an immediate re-subscribe. The
`_pendingExpiry` flag is set when a turn deadline fires while offline; the
expiry nudge is deferred until connectivity is restored so the server call can
succeed.

No status gate is applied — both streams are invalidated regardless of game
status (waiting, ready, active). The streams auto-dispose when their provider is
no longer watched, so invalidating during pre-game is harmless.

### Observation Snackbar (`_onObservation`)

`_onObservation` is registered via `ref.listenManual` in `initState` and uses a
single `switch` statement with a `mounted` guard at the top:

```dart
void _onObservation(AsyncValue<Observation>? prev, AsyncValue<Observation> next) {
  if (!mounted) return;
  switch (next) {
    case AsyncData(:final value):
      if (_errorSnackBarShown) {
        _errorSnackBarShown = false;
        ScaffoldMessenger.of(context).clearSnackBars();   // dismiss live snackbar
      }
      if (_pendingAction == _PendingAction.submittingAction) {
        setState(() => _pendingAction = null);
      }
      _scheduleDeadlineTimer(value.turnDeadline);
    case AsyncError():
      // …show "Connection lost. Retrying…" (or "This game has ended." when the
      // game is terminal) — one snackbar per error episode via _errorSnackBarShown
    default:
      break;
  }
}
```

`_errorSnackBarShown` is a debounce flag covering both the reconnecting and the
terminal ("This game has ended.") snackbars — without it, Riverpod's retry cycle
would re-show the snackbar on every failed attempt. `clearSnackBars()`
explicitly dismisses it on the first successful observation after reconnect;
resetting the flag alone is insufficient because the visible snackbar would
otherwise persist until its own 10-second `duration` expires.

### Stale-Data Fallback in `build()`

`_GameScreenState.build()` uses a guarded `switch` on `gameAsync` so the game UI
is preserved during Riverpod retry cycles:

```dart
switch (gameAsync) {
  _ when gameAsync.value != null => _GameBody(game: gameAsync.value!, …),
  AsyncError(:final error)      => _ErrorState(error: …, onRetry: _retryConnection),
  _                             => const CircularProgressIndicator(),
}
```

`gameAsync.value` is non-null for both `AsyncData` (normal) and `AsyncError`
with a previous value (Riverpod 3.x carries stale data in `AsyncError.value`).
The first arm matches both, keeping the board visible while the
`_ReconnectingBanner` communicates the reconnecting state. The `AsyncError` arm
(error with no stale data) only fires on a cold-start failure before any data
has arrived.

### Files

| File                                                      | Role                                                                                           |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `lib/core/connectivity/connectivity_provider.dart`        | `connectivityProvider` + `isOfflineProvider`                                                   |
| `lib/shared/widgets/status_banner.dart`                   | `StatusBanner` — slim full-width banner primitive                                              |
| `lib/core/navigation/widgets/shell_scaffold.dart`         | `_OfflineBanner` — shown on all shell screens                                                  |
| `lib/features/game/data/game_repository.dart`             | `_channelStream<T>` — Realtime channel helper; `gameStream()` and `observationStream()`        |
| `lib/features/game/providers/game_providers.dart`         | `gameStreamProvider` + `gameObservationProvider` — plain `@riverpod` (inherits `defaultRetry`) |
| `lib/features/game/presentation/screens/game_screen.dart` | `_ReconnectingBannerSlot`, `_ReconnectingBanner`, `_onConnectivityChange`, `_onObservation`    |

---

## 20. Push Notifications (FCM)

Push notifications are **infra-owned** — game implementors do not call the
notification service or register FCM tokens. All wiring happens automatically in
`AppStartup`.

### Packages

| Package                       | Purpose                                                                 |
| ----------------------------- | ----------------------------------------------------------------------- |
| `firebase_messaging`          | FCM token registration, background/foreground message delivery          |
| `flutter_local_notifications` | Shows a notification banner on Android/iOS when the app is foregrounded |

### Architecture

```
lib/core/notifications/
├── firebase_notification_service.dart  # FCM implementation
└── notification_provider.dart          # notificationServiceProvider (keepAlive)
                                        # notificationPermissionStatusProvider (auto-dispose)
```

`AppStartup.initState` registers on `navigationStream` first (stored in
`_notificationSub`), then calls `initialize()` inside a try/catch. The
listener-before-init order ensures the initial-message path (terminated-state
tap) is never missed on a broadcast stream.

`notificationPermissionStatusProvider` fetches the current `AuthorizationStatus`
on demand and is **not** keepAlive — it auto-disposes.
`AppLifecycleListener.onResume` in `AppStartup` calls
`ref.invalidate(notificationPermissionStatusProvider)` so the Settings screen
always reflects the current OS permission state after the user returns from
system Settings.

### What `initialize()` does

1. Creates three Android notification channels (see §Notification categories).
2. Calls `setForegroundNotificationPresentationOptions` so iOS shows banners
   while foregrounded.
3. Initialises `flutter_local_notifications` for foreground banners.
4. Requests OS permission once, gated by a `SharedPreferences` flag — dialog
   appears only on first launch.
5. Calls `getToken` (passing `vapidKey` on web) to force FCM registration — the
   result is discarded; the device's Firebase Installation ID (FID) is the
   stored identity. Reads it via `FirebaseInstallations.getId()` and upserts via
   `app_upsert_device_installation(p_fid, p_platform)` RPC.
6. Subscribes to `FirebaseInstallations.onIdChange` to re-upsert if the FID
   changes.
7. `FirebaseMessaging.onMessage` → shows a local notification banner, except
   `your_turn` notifications for the game the user is currently viewing: the
   handler reads `goRouterProvider`'s current URI and suppresses the banner if
   the user is already on `/game/{gameId}` matching the notification's deep
   link. Background delivery is unaffected — the OS renders those banners
   directly without passing through this handler.
8. `FirebaseMessaging.onMessageOpenedApp` + `getInitialMessage()` → emits
   `message.data['deep_link']` on `navigationStream`.

### Background handler

```dart
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}
```

Runs in an isolated context for terminated-state messages. Re-initialises
Firebase so the plugin messenger is available; takes no other action — the OS
renders the notification from the `notification` payload automatically.

### Notification categories

Three Android channels give users per-category system-level control. iOS uses
`InterruptionLevel` to match priority:

| Channel id             | Name             | Importance | iOS level       | Triggered by                          |
| ---------------------- | ---------------- | ---------- | --------------- | ------------------------------------- |
| `your_turn`            | Your Turn        | High       | `timeSensitive` | `observations` INSERT or UPDATE       |
| `game_invites`         | Game Invites     | Default    | `active`        | `games` INSERT (`access = 'friends'`) |
| `social_notifications` | Social & Friends | Low        | `active`        | `relationships` INSERT                |

`your_turn` is the default FCM channel (`AndroidManifest.xml`) so
system-delivered background notifications fall back to it when no `channelId` is
specified.

### `device_installations` table

| Column       | Type        | Notes                                             |
| ------------ | ----------- | ------------------------------------------------- |
| `fid`        | text        | **PK** — Firebase Installation ID (FCM v1 target) |
| `user_id`    | uuid        | FK → `auth.users`, cascade delete; indexed        |
| `platform`   | text        | `'ios'`, `'android'`, or `'web'`                  |
| `updated_at` | timestamptz | Refreshed on every upsert                         |

The FCM v1 API deprecated the registration `token` target in favour of the
`fid`. The PK is `fid` (one physical install → exactly one current user):
signing in claims the device from any prior owner via
`ON CONFLICT (fid) DO UPDATE SET
user_id = auth.uid()`, so account-switching on
a shared device can't leave a stale association. A user with several devices has
one row per FID; `_engine/fcm.ts` fans out by `user_id` (hence the index) and
notifies all of them.

### Installation lifecycle

**Registration**: driven by **auth state**, not app start. On `signedIn` /
`initialSession` (`app_startup._onAuthStateChange`), `registerInstallation()`
upserts the `(current user, FID)` row. It's auth-driven because the row maps a
_user_ to the device's FID, and `FirebaseInstallations.onIdChange` is
user-agnostic (it fires at FID birth, before sign-in) — so a FID event can never
carry "who just logged in". A `SharedPreferences` guard stores the
last-registered `userId:fid` and skips the write when unchanged, so a returning
user's launch costs nothing. `initialize()` still calls `getToken` once to force
FCM registration (a FID only resolves to a live registration once the device has
one); `onIdChange` re-registers the current user on the rare FID rotation.

**Sign-out**: `AuthController.signOut` calls `deleteCurrentInstallation()`
before clearing the session — it deletes only the DB row (and clears the local
guard) so the server stops targeting this user on this device. It deliberately
leaves the FCM registration intact (dropping it wouldn't re-establish until the
next process start, breaking same-session re-sign-in) and never deletes the
Firebase installation (that would reset Crashlytics/Remote Config/A&B identity).

**Cleanup**: There is no scheduled job. Unlike an FCM token, a FID does not
rotate, so there is no staleness heartbeat to age out. Rows are removed by three
authoritative signals: sign-out (above), account deletion (CASCADE from
`auth.users`), and send-time pruning — `_engine/fcm.ts` drops any FID FCM
reports permanently invalid (`UNREGISTERED` / `SENDER_ID_MISMATCH`). A dead FID
never targeted again lingers harmlessly until the next send prunes it.

### FCM message data payload

| Field       | Values                                                                                   | Purpose                 |
| ----------- | ---------------------------------------------------------------------------------------- | ----------------------- |
| `deep_link` | `/game/<id>` (your_turn), `/join/<short_code>` (game_invite), `/social` (friend_request) | Navigation on tap       |
| `category`  | `your_turn`, `game_invite`, `friend_request`                                             | Android channel routing |

### Server-side notification dispatch

The **edge function** emits every notification — there are no Postgres notify
triggers and no `pg_net` calls to FCM. After a commit (or after the relevant
route), the EF looks up the recipient's devices and sends directly. The two
modules involved:

- `_engine/fcm.ts` — the pure FCM HTTP v1 sender. It **mints and caches its own
  Google OAuth2 access token in-process** from the `FIREBASE_*` secrets
  (`FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY` → RS256-signed JWT → token
  exchange), refreshing it before expiry. This replaces the former
  `refresh-fcm-token` function + `pg_cron` + `app_config` token cache. It does
  no database access.
- `_engine/notify.ts` — the orchestration side. `pushToUser` loads the target's
  `device_installations` rows (via `_engine/repo.ts`, which owns every query),
  calls `fcm.ts` to fan out by FID, and prunes any FID FCM reports permanently
  invalid (`UNREGISTERED` / `SENDER_ID_MISMATCH`). Zero rows = no HTTP calls; if
  FCM is not configured it logs and returns early (graceful in local dev).

**Sources** (all EF-side, post-commit or in-route):

| Source                                            | When                                                                                                                                    | Notifies                                                                                                                                             |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `notifyTransition` (post-commit)                  | A seat newly enters `pending_players` (covers the version-0 start, so initially-pending players get the first-move push)                | Human seat → FCM "your turn" push; server-bot seat → signed wake POST to `webhook_url` (HMAC `x-wake-signature`, carrying the observation). See §26. |
| `notifyGameInvite` (`/game/create`)               | A `friends`-access game is created (public games are lobby-discoverable, not pushed — pushing every public game to all friends is spam) | All accepted friends of the creator                                                                                                                  |
| social route handlers (`friend-request`/`accept`) | A friend request is sent or accepted                                                                                                    | The other party                                                                                                                                      |

**Why EF-side, not triggers.** The EF already holds the committed transition
(the roster, the previous/final pending sets, the observation payloads), so it
can decide recipients without any extra DB read a trigger would need. Sends are
best-effort and fired after the commit returns, so notification latency never
extends the game write path. The earlier design routed these through
`AFTER … FOR EACH ROW` triggers + `pg_net`; collapsing them into the EF removed
the token cache, the cron, and a class of trigger-ordering concerns.

**`pg_net` extension**

`pg_net` is pre-installed and always enabled in Supabase. Migrations include
`CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions` — the
`WITH SCHEMA extensions` qualifier places the extension in the `extensions`
schema rather than `public`, avoiding the Supabase linter warning about
public-schema extensions. `pg_cron` requires explicit enabling via
`CREATE EXTENSION IF NOT EXISTS pg_cron` (no schema qualifier — it manages its
own `cron` schema).

### Security

Notification dispatch has **no PostgREST surface**: there is no public RPC for
token storage or sending, so nothing for a client to invoke. The Google service
account credentials (`FIREBASE_CLIENT_EMAIL` / `FIREBASE_PRIVATE_KEY` /
`FIREBASE_PROJECT_ID`) live only as edge-function environment secrets, and
`_engine/fcm.ts` mints the OAuth token in-process — the credential never touches
the database. `pushToUser` reads `device_installations` with the service-role
client inside the EF; clients can only read their **own** device rows under RLS
and never see another user's FIDs.

### Android notification icon

Android API 21+ ignores colour in notification icons — the system composites the
icon's alpha channel against its own tint (white on a dark background). Using
the full-colour launcher icon (`@mipmap/ic_launcher`) causes the system to
render a solid white box.

The correct approach is a monochrome silhouette vector drawable at
`android/app/src/main/res/drawable/ic_notification.xml`. It is referenced in
three places:

| Location                                                                                             | Usage                                                                 |
| ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `AndroidManifest.xml` — `com.google.firebase.messaging.default_notification_icon` meta-data          | FCM-delivered notifications (background and terminated state)         |
| `AndroidInitializationSettings('@drawable/ic_notification')` in `firebase_notification_service.dart` | `flutter_local_notifications` foreground banners                      |
| `AndroidNotificationDetails(icon: '@drawable/ic_notification')` in `_showForegroundNotification`     | Per-notification override (ensures consistency across all show calls) |

The drawable is a `<vector>` XML, not a raster PNG — no per-density variants are
needed, Android scales it perfectly at any size. The shape should be a
simplified monochrome silhouette of the app's launcher icon foreground.

`flutter_launcher_icons` does not support notification icon generation (it
generates launcher icons only). `ic_notification.xml` is a one-time
manually-maintained asset — it only needs to change if the app rebrands.

### `_NotificationCategory` strictness

`_NotificationCategory.fromString` throws `ArgumentError` for any unknown or
missing `category` field in the FCM data payload — it never returns `null` and
has no fallback channel. Every notification sent from the server must include an
explicit, known `category`. This is intentional: a silent fallback would hide
misconfigured server-side triggers, making bugs invisible until a user reports
missing notifications.

### iOS setup (one-time per deployment)

1. Xcode → Runner target → Signing & Capabilities → add **Push Notifications**
   and **Background Modes** (check Remote notifications).
2. Firebase Console → Cloud Messaging → Apple app configuration → upload APNs
   `.p8` key.
3. `flutterfire configure` generates `ios/Runner/GoogleService-Info.plist` —
   gitignored. For iOS CI, encode it and add as a GitHub Actions secret:
   ```bash
   base64 -i ios/Runner/GoogleService-Info.plist | pbcopy  # → GOOGLE_SERVICE_INFO_PLIST_BASE64
   ```
   Decode it in the iOS workflow before the build:
   ```yaml
   - name: Decode Firebase config
     run: |
       echo "${{ secrets.FIREBASE_OPTIONS_DART_BASE64 }}" | base64 --decode > lib/firebase_options.dart
       echo "${{ secrets.GOOGLE_SERVICE_INFO_PLIST_BASE64 }}" | base64 --decode > ios/Runner/GoogleService-Info.plist
   ```

### Web setup (not yet active — required before enabling web notifications)

1. Firebase Console → Project Settings → Cloud Messaging → Web Push certificates
   → Generate key pair → copy the public key.
2. Add `FIREBASE_VAPID_KEY=<public-key>` to `.env` and run
   `dart run build_runner build`.
3. Add `web/firebase-messaging-sw.js` (service worker required by the Web Push
   Protocol for background delivery):
   ```js
   importScripts(
     "https://www.gstatic.com/firebasejs/10.x.x/firebase-app-compat.js",
   );
   importScripts(
     "https://www.gstatic.com/firebasejs/10.x.x/firebase-messaging-compat.js",
   );
   firebase.initializeApp({/* same config as firebase_options.dart */});
   firebase.messaging().onBackgroundMessage((payload) => {
     self.registration.showNotification(payload.notification.title, {
       body: payload.notification.body,
       icon: "/icons/Icon-192.png",
     });
   });
   ```
4. The Flutter code already passes
   `vapidKey: kIsWeb ? Env.firebaseVapidKey : null` to `getToken()` and detects
   `'web'` platform in `_upsertToken`. No further code changes needed — setting
   the env var is sufficient to activate web tokens.

### OAuth token lifetime

Google access tokens obtained via the JWT bearer grant (RFC 7523) are
**contractually** 3600 seconds. `_engine/fcm.ts` requests `exp: now + 3600` and
caches the resulting access token in process memory, refreshing it lazily a
little before expiry — so an actively-serving function holds at most one live
token and re-mints only when needed. There is no cron, no shared token cache,
and no cross-request staleness window: a cold function simply mints on first
send. A failed mint surfaces as a logged error on that send (the push is lost,
not retried); the next send re-attempts.

### Supabase edge function secrets

The `_engine/fcm.ts` sender requires three Firebase secrets. These are edge
function environment variables, not Vault secrets — they are set once per
project via the CLI or Dashboard and are invisible to client code.

Only two fields from the service account are used — `client_email` (the JWT
issuer) and `private_key` (for RS256 signing). The full JSON blob is never
needed.

**Obtaining the values:**

1. Firebase Console → Project Settings (gear icon) → **Service accounts** tab.
2. Click **Generate new private key** → **Generate key** → a `.json` file
   downloads.
3. Open the file and copy only:
   - `client_email` — looks like
     `firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com`
   - `private_key` — the full PEM block including `-----BEGIN PRIVATE KEY-----`
     header/footer
4. Delete the downloaded file — it grants Firebase Admin access and should never
   be stored.

**Setting the secrets:**

```bash
supabase secrets set FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com
supabase secrets set FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
"

# If setting via a script, use $'...' syntax so \n becomes real newlines:
# supabase secrets set FIREBASE_PRIVATE_KEY=$'-----BEGIN PRIVATE KEY-----\nABC...\n-----END PRIVATE KEY-----\n'
# The function also normalises literal \n at startup as a safety net.

# Shown in Firebase Console → Project Settings → General.
supabase secrets set FIREBASE_PROJECT_ID=<your-project-id>
```

**Local dev**: FCM sends will not work without real Firebase credentials. This
is expected — `pushToUser` checks `getFirebaseEnv()` and degrades gracefully
with a warning when the `FIREBASE_*` secrets are absent, so local play is
unaffected. Do not add placeholder Firebase values to `.env.local`.

After setting secrets, deploy the `engine` function (see §21).

Secrets are project-wide; the `engine` function reads:

| Secret                  | Used by                                                                  |
| ----------------------- | ------------------------------------------------------------------------ |
| `FIREBASE_CLIENT_EMAIL` | `_engine/fcm.ts` — JWT issuer claim for the Google OAuth2 token exchange |
| `FIREBASE_PRIVATE_KEY`  | `_engine/fcm.ts` — RS256 signing key for the JWT                         |
| `FIREBASE_PROJECT_ID`   | `_engine/fcm.ts` — used to build the FCM v1 endpoint URL                 |
| `BOT_SIGNING_SECRET`    | `_engine/bot_auth.ts` — master key; per-bot key = `HMAC(master, bot_id)` |

The cron/`pg_net` routes (`/engine/internal/*`) need no function-side secret:
`@supabase/server`'s `auth: 'secret'` mode validates the caller's `apikey`
header against the platform-injected `SUPABASE_SECRET_KEY` (the caller-side copy
lives in Vault as `secret_api_key` — §8).

### Files

| File                                                          | Role                                                                                                                                                                                                         |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/core/notifications/firebase_notification_service.dart`   | FCM implementation                                                                                                                                                                                           |
| `lib/core/notifications/notification_provider.dart`           | `notificationServiceProvider` (keepAlive) + `notificationPermissionStatusProvider` (auto-dispose, invalidated on resume)                                                                                     |
| `lib/core/startup/app_startup.dart`                           | Calls `initialize()`, stores `_notificationSub`, routes `navigationStream` taps via `navigateFromNotification`                                                                                               |
| `android/app/src/main/res/drawable/ic_notification.xml`       | Monochrome silhouette vector — used as the Android notification icon for both foreground (`flutter_local_notifications`) and background/terminated-state (FCM direct delivery) notifications                 |
| `android/app/src/main/AndroidManifest.xml`                    | `com.google.firebase.messaging.default_notification_icon` meta-data points to `@drawable/ic_notification`                                                                                                    |
| `supabase/migrations/20260518081308_device_installations.sql` | `device_installations` table, `app_upsert_device_installation`/`app_delete_device_installation` RPCs, monthly cleanup                                                                                        |
| `supabase/functions/_engine/fcm.ts`                           | FCM v1 sender — mints + caches its own OAuth token in-process (replaces the former `refresh-fcm-token` function + cron + `app_config` cache)                                                                 |
| `supabase/functions/_engine/notify.ts`                        | All EF-direct pushes: post-commit "your turn" + signed server-bot wakes, plus the friends-game invite (`/game/create`) and friend-request / accepted pushes (`social` routes). No SQL notify triggers exist. |

---

## 21. Edge Functions

### Why rules run as TypeScript in Edge Functions

Game rules are **pure TypeScript** (the app's `_lib/game.ts` gameModule) run in
an Edge Function, while the DB keeps lock/version/timing/persistence behind
gated `engine_*` RPCs. TypeScript is the right home for complex rules (Poker
side-pots/hand-ranking, multi-player elimination): expressive, testable, and
library-rich, while the engine's correctness guarantees (atomic, serialized,
hidden-info-safe) stay enforced in SQL.

Why the EF — and not in the database transaction — is the orchestration layer:

- **Compute is not the bottleneck.** Resolving a move/hand is sub-millisecond;
  the scaling drivers (DB write throughput, Realtime fan-out, storage) are
  identical wherever rules run, so _where_ rules execute is a
  developer-experience choice, not a throughput one. (Target scale: ~5,000
  games/day, peak ~1,000 simultaneous — turn-based, latency-tolerant.)
- **The lock is RPC-internal.** The `FOR UPDATE` lock lives entirely inside one
  commit RPC (`BEGIN → lock → validate → write → COMMIT`). EF↔DB distance adds
  to per-action latency (irrelevant for turn-based) but does **not** extend
  lock-hold, so it does not cap throughput.
- **Postgres can't synchronously call out over HTTP** — only async `pg_net`. So
  rules can't run synchronously inside the commit transaction under the lock;
  the orchestration that calls them lives in the EF, with Postgres invoked _by_
  the EF (read → compute → commit), never the reverse.

Alternative platforms: **Cloudflare Workers/Durable Objects** are excellent and
slightly cheaper, with a stateful per-game DO per game (an actor-model fit), but
that only pays off at a scale we are nowhere near, and it adds a second platform
and a powerful Supabase key in a third-party store. A persistent stateful game
server (VM/container) has the best high-scale ceiling but is premature here.
Edge Functions keep one vendor, co-located with the DB, with the smallest
security surface and one CI/CD toolchain. The choice is **reversible**: the
rules module is pure TS, so a future move is a transport-layer swap, not a rules
rewrite.

### Function inventory

There is **one** edge function, **`engine`** (`verify_jwt = false` — auth is per
route group inside the function, so the platform-level JWT check must not reject
the non-JWT callers). One function means one warm worker (fewer cold starts),
one deploy, and one import map — the consolidation Supabase itself recommends
for related routes. It is built on the `_engine/*` framework and the app's
single `_lib/game.ts` gameModule, and serves four route groups split by
`withSupabase` auth mode:

- **`/engine/game/*`** — client-facing, `auth: 'user'`. Every route requires a
  verified user JWT (verified in-lib via JWKS); the middleware injects the
  service-role client. Routes: create / create-solo / add-bot / action / start /
  forfeit / replay / local-bot-action / delete-account / expire (the participant
  nudge).
- **`/engine/social/*`** — client-facing friend writes, `auth: 'user'`. Routes:
  friend-request / accept / remove. Game-agnostic (never touches the
  gameModule); emits friend-request / accepted pushes directly.
- **`/engine/internal/*`** — DB/cron, `auth: 'secret'`. Driven by Postgres
  (`pg_cron` → `pg_net`) posting the project's secret API key as the `apikey`
  header (from Vault `secret_api_key` — §8). Two **batched** routes: `expire`
  (`{ game_ids }`, the timeout sweep) and `purge-users` (`{ user_ids }`, the
  stale-guest forfeit-then-purge). Both reuse the same `resolveLifecycle` core as the
  client `forfeit` / `delete-account` / `expire` routes. (The group prefixes
  also disambiguate `game/expire` vs `internal/expire`.)
- **`/engine/bot/*`** — server bots (possibly external), `auth: 'none'`. A
  single `action` route, authenticated by a per-bot HMAC the handler verifies
  in-process.

Ratings (OpenSkill) and FCM sending run inside the framework as `_engine/*`
modules — there is no separate `update-ratings` or `refresh-fcm-token` function.
Server bots POST to the `/engine/bot/action` route, authenticated by a per-bot
HMAC the EF verifies in-process with a key derived from `BOT_SIGNING_SECRET`
(see §26). See migration §12.

### Local development

The Supabase CLI serves the function locally:

```bash
supabase functions serve
```

Secrets for local serving live in `supabase/functions/.env.local` (not
committed): the Firebase vars and `BOT_SIGNING_SECRET` when needed, plus
`SUPABASE_SECRET_KEY` if your CLI version doesn't inject it — `@supabase/server`
resolves the secret key from `SUPABASE_SECRET_KEY`/`SUPABASE_SECRET_KEYS` for
both the admin client and `auth: 'secret'` validation. The Vault
`secret_api_key` (see `seed.sql`) must hold the same value so the local cron
sweeps authenticate.

`SUPABASE_URL` is injected automatically by the CLI — do not add it to
`.env.local`.

**Firebase secrets** (`FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`,
`FIREBASE_PROJECT_ID`) are intentionally absent from `.env.local`. With them
unset, `getFirebaseEnv()` returns null and `pushToUser` degrades gracefully
(warning + early return) — `_engine/fcm.ts` never mints a token. Push
notifications simply don't fire in local dev.

**Firebase app** (`firebase_options.dart`): Firebase is mandatory — the app will
not compile without this file. Run `flutterfire configure` once when first
setting up the project, even for local development. The generated file connects
to a real Firebase project; Analytics and Crashlytics events will appear there
during local dev runs.

### Production deployment

Set all secrets first (§8 for the Vault `secret_api_key`; §20 for Firebase
secrets), then deploy:

```bash
supabase functions deploy engine
```

Re-run this command any time function code changes. Secrets do not need to be
re-set on redeploy — they persist in the project.

There is no automated CD for edge functions in the CI workflow. Deployment is a
manual step performed alongside database migrations when releasing changes that
touch function code.

---

## 22. Account Deletion

Account deletion is **infra-owned**. It is exposed to the client via the
`game/delete-account` edge-function route and surfaces in the UI as a
destructive action in Settings (bottom of the screen, `colorScheme.error`
styling, confirmation dialog).

### Client-Side Flow

```
AuthController.deleteAccount()
  1. deleteUserData(ref, userId)             ← clears SQLite profile cache (unsafe_forever never expires on its own)
  AuthService.deleteAccount()
  2. Best-effort avatar removal from storage ('avatars' bucket, object name = userId)
  3. supabase.functions.invoke('game/delete-account')  ← the single server call
  4. supabase.auth.signOut()                 ← best-effort; swallow errors

AuthController.signOut()
  1. deleteUserData(ref, userId)             ← clears SQLite profile cache
  2. notificationService.deleteCurrentInstallation() ← best-effort FCM registration removal
  3. supabase.auth.signOut()
```

Avatar removal is done client-side first because storage is separate from the DB
transaction — after `auth.users` is deleted the client has no credentials to
call the Storage API. If it fails (avatar not found, network error), deletion
continues.

`deleteUserData` deletes the user-scoped SQLite keys (`profile_<userId>`,
`friendships_<userId>`) before the session ends. This is necessary because
`StorageCacheTime.unsafe_forever` never expires automatically — without explicit
deletion, a subsequent login as a different account on the same device could
theoretically read stale keys. See §23 for the full persistence design.

`signOut()` after a successful `game/delete-account` call will likely fail (the
auth session is already gone) — those errors are caught and silently dropped.
Navigation back to the auth screen is driven by the existing
`authStateChangesProvider` listener reacting to the session becoming null.

### Server-Side Flow (`game/delete-account` route)

The `game/delete-account` edge-function route calls `purgeUserGames`, which
**forfeits first** (the consequence needs the rules) then runs a pure-SQL purge.
Active-game forfeits go through the normal commit path; the teardown
(`engine_purge_user`) is one SQL transaction, and all lobby cleanup happens
**before** `DELETE FROM auth.users`:

```
game/delete-account            (edge function, caller JWT)
  └── purgeUserGames (EF)
      ├── readActiveGameIds(user)          ← the user's active games (typed SDK read)
      ├── FOR each active game:  forfeit via the EF
      │     applyLifecycle('forfeit') → engine_commit_action
      │       ├── INSERT game_states (new version) + actions (type='system')
      │       ├── on finish: INSERT game_outcomes, games.status='finished',
      │       │     and rating updates written in the SAME transaction (rated games)
      │       └── fans out per-player observations
      └── engine_purge_user(user)          ← single SQL transaction
            ├── FOR each waiting/ready game CREATED:  do_cancel_game  (status='aborted')
            ├── FOR each waiting/ready game JOINED:   do_leave_game   (compacts
            │                                          player_index, ready→waiting)
            └── DELETE FROM auth.users WHERE id = user
                  └── CASCADE → public.users
                        ├── CASCADE → user_profiles           (deleted)
                        ├── CASCADE → relationships            (deleted — both sides)
                        ├── CASCADE → player_ratings           (deleted)
                        ├── CASCADE → rating_history           (deleted)
                        ├── SET NULL → games.created_by        (preserved, anonymized)
                        ├── SET NULL → participants.user_id    (preserved, seat retained)
                        ├── SET NULL → game_outcomes.user_id   (preserved, anonymized)
                        ├── SET NULL → actions.user_id         (preserved, audit retained)
                        └── CASCADE → observations.user_id     (deleted — no longer needed)
                  └── CASCADE → device_installations (auth.users fk)  (deleted)
```

The same `purgeUserGames` path backs the stale-guest cleanup
(`internal/purge-users`), which batches guests that still hold active games;
guests with no active games are purged in pure SQL by the cron sweep with no
edge-function hop. See §25 / §21.

A forfeit's consequence is game-defined: in a 3+ player game it may leave the
game **active**, so the purged seat (both ids NULL) can exist in a live game.
The remaining players continue normally — subsequent commits skip the seat in
the observation fan-out (`write_observation_slices`: no viewer, no slice), a
later rated finish keeps the seat in the OpenSkill field but emits no rating
write for it (`computeRatings`), and clients render it as "Deleted User".
Replay for the others is unaffected: `game_states`/`actions` are game-keyed,
and each player reads only their own observation history.

The harness asserts the game-side half of this contract next to
`assertHookState` (game bug → 500, before commit): `assertForfeitPending` —
a forfeit hook must remove its target seat from the pending set, or the purge
would leave a ghost seat holding a deadline the timeout sweep fires at
forever — and `assertPendingIdentified` — no hook may return an identity-less
seat as pending (backstop against rules resurrecting a purged seat later).

#### Why forfeit + cancel/leave before the cascade?

A plain `DELETE FROM auth.users` would SET NULL on `participants.user_id` and
leave orphaned lobby rows (and abandon other players in active games).
`engine_purge_user`'s `do_cancel_game` / `do_leave_game` run the proper cleanup
— compacting `player_index`, transitioning status, preserving lobby integrity —
and the EF forfeits active games first so opponents aren't stuck. The cascade
alone knows nothing about these invariants.

#### Why no version handshake on the forfeits?

The forfeit takes no `expected_version` — forfeiting is an unconditional intent.
`engine_commit_action` acquires the `FOR UPDATE` lock on `games` and reads the
latest `game_states` row under it, so the committed action is always correctly
ordered even if other players act concurrently.

### What is Preserved

Game history is preserved for other players and for future analysis:

| Data                   | Fate                                                                             | Reason                                                         |
| ---------------------- | -------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `game_states` rows     | **Preserved** (game ON DELETE CASCADE does not fire; the game row stays)         | Immutable append-only history; needed for replay and audit     |
| `actions` rows         | **Preserved** — `user_id` SET NULL; `player_index` intact                        | Audit log and replay attribution via `player_index`            |
| `game_outcomes` rows   | **Preserved** — `user_id` SET NULL; `player_index`, `result`, `placement` intact | Analytics and rating history for other players                 |
| `participants` rows    | **Preserved** for finished games — `user_id` SET NULL                            | `gamePlayersProvider` needs the seat to display "Deleted User" |
| `player_ratings`       | **Deleted** (CASCADE)                                                            | No identity → no leaderboard entry                             |
| `rating_history`       | **Deleted** (CASCADE)                                                            | Personal audit log; meaningless without an account             |
| `user_profiles`        | **Deleted** (CASCADE)                                                            | Personal data                                                  |
| `relationships`        | **Deleted** (CASCADE from both sides)                                            | Social graph                                                   |
| `observations`         | **Deleted** (CASCADE)                                                            | Derived data; regenerable from `game_states` on replay         |
| `device_installations` | **Deleted** (CASCADE from auth.users)                                            | No account → no push delivery                                  |
| Avatar file            | **Deleted** (client-side first)                                                  | Storage is not in the DB transaction                           |

### Rating Updates During Deletion

Ratings are computed in the EF and written by `private.apply_rating_updates`
**inside the finishing transaction** (see §8). Deletion sequences this cleanly:
`purgeUserGames` **forfeits the caller's active games first** (each forfeit is
its own commit, so any rated forfeit applies its rating updates while the user
row still exists), and only then does `engine_purge_user` cancel/leave the
remaining lobby games and `DELETE FROM auth.users`. So the deleting player's own
rating writes complete before their `public.users` row is gone.

`apply_rating_updates` still keeps an existence guard as defense-in-depth, so a
finishing game that references an already-removed identity simply skips that
player while the others are rated normally:

```sql
IF v_user_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM public.users WHERE id = v_user_id
) THEN
  CONTINUE;  -- skip deleted user, other players still get their update
END IF;
```

### Dart-Side Null Handling

After deletion, `participants.user_id` and `participants.bot_id` are both NULL
for the deleted player's seat on finished games. `gamePlayersProvider` handles
this explicitly:

```dart
// In gamePlayers provider:
final id = p.userId ?? p.botId;
if (id != null) {
  // normal path — resolve via playerInfoCacheProvider
} else {
  // deleted player — construct a synthetic identity, flag isDeleted
  return Future.value(MapEntry(p.playerIndex,
    GamePlayer(…, info: _deletedPlayerInfo(gameId, p.playerIndex), isDeleted: true)));
}

PlayerInfo _deletedPlayerInfo(String gameId, int playerIndex) => PlayerInfo(
  id: 'deleted_${gameId}_$playerIndex',  // scoped to game+seat for widget key uniqueness only
  username: 'player_$playerIndex',
  displayName: 'Deleted User',
);
```

`GamePlayer.isDeleted` is the correct guard for UI decisions — never inspect
`PlayerInfo.id` directly. The synthetic ID's only role is to give each deleted
seat a distinct widget key; it is not a database UUID and must not be passed to
identity lookups or `PlayerProfileSheet.show`. `displayName` is `'Deleted User'`
— shown anywhere the player's name appears in the game screen or history.

### Settings UI

`_DeleteAccountTile` — placed at the bottom of the Settings screen with no
section label, `colorScheme.error` styling throughout (icon, title, chevron).

`_DeleteAccountDialog` — `AlertDialog` with a plain-language warning
("permanently deletes your account, all your games, and your ratings. This
cannot be undone."), a Cancel button, and a filled Delete button styled with
`colorScheme.error`. While the RPC is in flight the button shows a 16 × 16
`CircularProgressIndicator` and both buttons are disabled. On error a `SnackBar`
surfaces the message and re-enables the button. On success the dialog is popped
— the `authStateChangesProvider` listener drives navigation to the sign-in
screen.

### Terms & Privacy Links

Terms of Service and Privacy Policy links in the Settings screen open using
`LaunchMode.inAppBrowserView` (`url_launcher`), which maps to
`SFSafariViewController` on iOS and Chrome Custom Tabs on Android. This mode is
required on iOS to prevent Universal Links interception — without it, iOS would
hand the URL back to the app's GoRouter, which throws a `GoException` because
neither `/terms` nor `/privacy` are declared routes. `inAppBrowserView` bypasses
the Universal Links handler entirely, keeping the browser session inside the app
without router involvement.

---

## 23. Local Persistence

### Goal

Eliminate cold-start spinners for data that is already known and unlikely to
have changed meaningfully since the last session. The first paint should show
real data; background refreshes update silently.

### Technology

`riverpod_sqflite` provides a `JsonSqFliteStorage` backend for Riverpod 3.x's
experimental `persist()` API. A single SQLite database (`riverpod.db`) stores
all persisted provider state as JSON strings, keyed by a string. One database
connection is opened at startup and shared by all providers.

### `storageProvider`

`lib/core/storage/storage_provider.dart` owns three things:

```dart
/// Shared SQLite backend — opened once, kept alive for the app lifetime.
@Riverpod(keepAlive: true)
Future<JsonSqFliteStorage> storage(Ref ref) async {
  return JsonSqFliteStorage.open(
    join(await getDatabasesPath(), 'riverpod.db'),
  );
}

/// User-scoped cache keys — centralised so providers and deleteUserData stay in sync.
String profileCacheKey(String userId) => 'profile_$userId';
String friendshipsCacheKey(String userId) => 'friendships_$userId';

/// Deletes all locally persisted data for [userId].
/// Call on sign-out and account deletion; unsafe_forever never expires on its own.
Future<void> deleteUserData(Ref ref, String userId) async {
  final storage = await ref.read(storageProvider.future);
  await Future.wait([
    storage.delete(profileCacheKey(userId)),
    storage.delete(friendshipsCacheKey(userId)),
  ]);
}
```

`storageProvider` is a **function-based `FutureProvider`**, not an
`AsyncNotifier`. It opens a resource once and never mutates state —
`AsyncNotifier` is for mutable state and would be the wrong abstraction here.

`deleteUserData` is a **free function**, not a method on a class. This avoids a
circular import: `auth_providers.dart` calls `deleteUserData`,
`profile_providers.dart` imports `auth_providers.dart`, and `deleteUserData`
needs `profileCacheKey` — putting all three in `core/storage` breaks the cycle.

Cache key helpers are intentionally kept in this file rather than in their
respective provider files for the same circular-import reason.

### Stale-While-Revalidate Pattern

Persisted providers race their SQLite restore against the network fetch
simultaneously:

```
build() called
  ├── persist() called — begins SQLite lookup (~5 ms)
  └── network fetch begins (~100–300 ms)
        │
        ▼
  SQLite wins first (typical cold start):
    state = AsyncData(cachedProfile)   ← no spinner, instant render
    network fetch completes → state = AsyncData(freshProfile)   ← silent update

  Network wins first (first-ever cold start, cache miss):
    state = AsyncData(freshProfile)    ← no stale intermediate
    SQLite result arrives → discarded (didChange guard inside persist())
```

`persist()` is called **without awaiting** it. Awaiting it would serialize the
two fetches and eliminate the performance benefit. The internal `didChange`
guard prevents stale SQLite data from overwriting a fresher network result.

### `CurrentUserProfile`

```dart
@Riverpod(keepAlive: true)
@JsonPersist()
class CurrentUserProfile extends _$CurrentUserProfile {
  @override
  Future<UserProfile> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) throw StateError('User not authenticated');

    persist(
      ref.watch(storageProvider.future),
      key: profileCacheKey(user.id),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        destroyKey: '1',
      ),
    );

    final repository = ref.watch(profileRepositoryProvider);
    return repository.getUserProfile(user.id);
  }
}
```

| Decision                          | Rationale                                                                                                                            |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `keepAlive: true`                 | Provider never auto-disposes; navigating away and back does not re-fetch                                                             |
| `@JsonPersist()`                  | Code-generates a typed `persist()` method using `UserProfile.fromJson`/`toJson`; no hand-written encode/decode                       |
| `key: profileCacheKey(user.id)`   | User-scoped: different accounts on the same device never share cached data                                                           |
| `StorageCacheTime.unsafe_forever` | Cache never expires on its own; explicit `deleteUserData` on sign-out handles eviction                                               |
| `destroyKey: '1'`                 | Bump this string whenever `UserProfile`'s JSON schema changes incompatibly — old cached entries are discarded and a fresh fetch runs |

`@JsonPersist()` works because `UserProfile` is a `@freezed` class with
`fromJson`/`toJson`. The generator reads those methods and produces a
`persist()` extension that handles the `String` encode/decode that
`JsonSqFliteStorage` requires.

### Cache Eviction

`StorageCacheTime.unsafe_forever` means entries survive until explicitly
deleted. Eviction must be triggered at the right moment:

- **Sign-out** (`AuthController.signOut`): `deleteUserData(ref, userId)` before
  `signOut()` — the userId is read while the session is still active.
- **Account deletion** (`AuthController.deleteAccount`): same pattern, same
  reason.
- **`playerInfoCacheProvider` entries are NOT cleared on sign-out.** Player
  identity (username, displayName, avatarUrl) is public data — a different
  account on the same device benefits from the same cache and seeing
  stale-then-fresh data for other players is harmless.
- **Profile mutations** (`uploadAvatar`, `updateProfileFields`):
  `CurrentUserProfile` calls
  `ref.invalidate(playerInfoCacheProvider(id: userId))` after each successful
  save so game screens and social views reflect the change immediately.

**Why per-key deletion, not file deletion?** Calling
`ref.invalidate(storageProvider)` while `currentUserProfileProvider` is watching
the storage provider would trigger an immediate rebuild —
`currentUserProfileProvider.build()` would re-call
`ref.watch(storageProvider.future)`, re-opening the database file before
deletion could finish. Per-key `storage.delete(key)` avoids this race entirely.

### `Friendships`

`Friendships` holds three `Mutation` objects as static fields. Widgets call
`Friendships.send(playerId).run(...)` etc. — each playerId gets an independent
in-flight state machine. The mutations live on the class (not in a separate
file) so the label and the notifier methods that execute them are co-located.

```dart
@Riverpod(keepAlive: true)
@JsonPersist()
class Friendships extends _$Friendships {
  static final send   = Mutation<void>(label: 'sendFriendRequest');
  static final accept = Mutation<void>(label: 'acceptFriendRequest');
  static final remove = Mutation<void>(label: 'removeFriend');

  @override
  Future<List<Friendship>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) throw StateError('User not authenticated');

    persist(
      ref.watch(storageProvider.future),
      key: friendshipsCacheKey(user.id),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        destroyKey: '1',
      ),
    );

    return ref.watch(socialRepositoryProvider).getFriendships();
  }
}
```

`Friendship` is a `@freezed` class with `fromJson`/`toJson`, so `@JsonPersist()`
works without any model changes. `RelationshipStatus` is a plain Dart enum;
`json_serializable` serialises it as its string name.

**Derived providers** (`acceptedFriends`, `pendingRequests`, `sentRequests`,
`friendStatus`) are auto-dispose `FutureProvider`s that watch
`friendshipsProvider.future` — they need no persistence of their own. When
`friendshipsProvider` updates (from cache or network), all derived providers
rebuild automatically. `friendStatusProvider(targetId: id)` derives a
`FriendStatus` enum value (`friends`, `incomingPending`, `outgoingPending`,
`none`) for a specific player; `FriendActions` uses this to decide which
button(s) to render.

**Notification-driven invalidation.** The shell-scaffold badge
(`pendingRequests`) and the Requests tab are the primary surfaces a user checks
after tapping a friend-request notification. If the Social screen is already
mounted when the notification arrives, `initState` is never called — the widget
is alive and stale. To close this gap, `AppStartup._onNotificationNavigation`
invalidates `friendshipsProvider` before navigating whenever the destination
path starts with `/social`:

```dart
void _onNotificationNavigation(String path) {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;
  if (path.startsWith('/social')) {
    ref.invalidate(friendshipsProvider);
  }
  GoRouter.of(context).navigateFromNotification(path);
}
```

Invalidation fires before `navigateFromNotification`, so the provider starts
refetching while the navigation transition animates. With persistence, the
cached list renders instantly; the fresh list arrives silently by the time the
animation completes.

### What Is and Is Not Persisted

| Provider                      | Persisted | Reason                                                                                                                                                                                                                                             |
| ----------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `currentUserProfileProvider`  | Yes       | Own profile; cold-start UX                                                                                                                                                                                                                         |
| `playerInfoCacheProvider(id)` | Yes       | Public player identity; eliminates per-player spinners on cold start                                                                                                                                                                               |
| `friendshipsProvider`         | Yes       | Social list; stale-while-revalidate + notification-driven invalidation                                                                                                                                                                             |
| `availableBotsProvider`       | Yes       | Bot catalog; deployment-global reference data, cold-start UX for the solo play/"Add bot" pickers and the local-bot driver. Like `playerInfoCacheProvider`, it is public and **not** user-scoped — auto-derived global key, not cleared on sign-out |
| `botCatalogByIdProvider`      | No        | Derived from `availableBotsProvider` (cheap reindex); rebuilds automatically when it updates                                                                                                                                                       |
| `playerRatingsProvider`       | No        | Rating data; excluded by design                                                                                                                                                                                                                    |
| `activeGamesProvider`         | No        | Real-time data; staleness would be misleading                                                                                                                                                                                                      |

### Pre-Warm at Auth

`AppStartup._onAuthStateChange` fires
`ref.read(currentUserProfileProvider.future).ignore()` on `initialSession` and
`signedIn` events. This starts the stale-while-revalidate cycle (SQLite
restore + network fetch) while the splash screen is still animating away.
Because the provider is `keepAlive`, the result is shared with all future
watchers — no second fetch occurs when the Profile screen opens.

The same line warms `availableBotsProvider`
(`ref.read(availableBotsProvider.future).ignore()`). This is deliberately
unconditional rather than gated on `module.localBots.isNotEmpty`: the shell
scaffold already warms the catalog for **local-bot** builds (it watches it to
decide the New Solo Game FAB), so the prewarm exists to ready the
**server-bots-only** path — where the shell's `localBots.isNotEmpty`
short-circuit means nothing watches it until the waiting-room "Add bot" picker
opens. The cost for a bot-less deployment is one cheap `app_bots` returning an
empty list, persisted once.

### Schema Migration

If `UserProfile` fields change in a way that makes cached JSON unparseable, bump
`destroyKey` from `'1'` to `'2'` (or any new string). All existing entries for
that key are discarded on the next launch and a fresh network fetch populates
the cache. This is the only migration path — there is no incremental JSON
migration mechanism.

### Files

| File                                                           | Role                                                                                                                                                                                          |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/core/storage/storage_provider.dart`                       | `storageProvider`, `profileCacheKey`, `friendshipsCacheKey`, `deleteUserData`                                                                                                                 |
| `lib/core/storage/storage_provider.g.dart`                     | Generated by `riverpod_generator`                                                                                                                                                             |
| `lib/features/profile/providers/profile_providers.dart`        | `CurrentUserProfile` — `keepAlive`, `@JsonPersist()`, `persist()`; invalidates `playerInfoCacheProvider` on mutations                                                                         |
| `lib/features/social/providers/social_providers.dart`          | `Friendships` — `keepAlive`, `@JsonPersist()`, `persist()`, static `Mutation` fields; `FriendStatus` enum; `friendStatusProvider`; invalidated by `AppStartup` on `/social` notification taps |
| `lib/features/social/presentation/widgets/friend_actions.dart` | `FriendActions` — routes on `FriendStatus`, compact/full layout variants                                                                                                                      |
| `lib/features/social/presentation/widgets/friend_buttons.dart` | `SendRequestButton`, `AcceptButton`, `RemoveFriendButton`, `DeclineRequestButton` — own their mutation state via `Friendships.{send,accept,remove}`                                           |
| `lib/shared/providers/player_providers.dart`                   | `PlayerInfoCache` — `keepAlive`, `@JsonPersist()`; key auto-generated from family `id` arg                                                                                                    |
| `lib/features/auth/providers/auth_providers.dart`              | `AuthController.signOut` / `deleteAccount` — call `deleteUserData`                                                                                                                            |
| `lib/core/startup/app_startup.dart`                            | Pre-warm `currentUserProfileProvider` in `_onAuthStateChange`; invalidate `friendshipsProvider` on `/social` notification taps                                                                |

### Dependencies

```yaml
dependencies:
  riverpod_sqflite: ^0.4.2 # JsonSqFliteStorage backend
  sqflite: ^2.4.2 # SQLite engine
  path: ^1.9.1 # getDatabasesPath join
```

`riverpod_sqflite` provides `JsonSqFliteStorage`. `sqflite` and `path` are
direct dependencies because `storage_provider.dart` imports them directly
(`depend_on_referenced_packages` lint).

---

## 24. Backward Compatibility — evolving the game without breaking shipped apps

This is the companion to
[README → Versioning & backward
compatibility](../README.md#versioning--backward-compatibility). That section
covers the **engine Dart API** and **engine SQL** contracts (semver,
expand/contract, the release/rollout flow). This section covers what bites once
a _game_ is in real users' hands and you want to change a rule or add a feature:
the **game JSONB payloads** (config / state / observation / action), the
**client caches**, and the **client↔server version negotiation** that bounds how
long old clients must be supported.

The guiding fact: once an app ships, client and server **no longer move
together**. Mobile update lag means a `v(n)` binary keeps calling a newer
backend for weeks, and a `Daily`-timed game can outlive several app releases.
Every change must answer: _"what does an old client, and an in-flight game
started under the old rules, do when they meet the new code?"_

### Three version axes (keep independent)

| Axis                     | Granularity              | Where it lives                                                                                                               | Who reads it                                              |
| ------------------------ | ------------------------ | ---------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| **Engine semver**        | per engine release       | git tag `vX.Y.Z`, `pubspec.yaml`                                                                                             | build/release                                             |
| **Game schema version**  | per game _type_ revision | `games.schema_version` column (selects the `GameRules` unit on both sides; surfaced on `Game` client-side)                   | `rulesFor` (TS harness) + `gameRulesProvider` (Dart)      |
| **Cache schema version** | per persisted model      | each provider's `destroyKey`                                                                                                 | `riverpod_sqflite` on cold start                          |

An engine release may touch none, one, or several of these.

### The five compatibility surfaces

| # | Surface                                                                                    | Breaks when                               | Mechanism                                                                                                           |
| - | ------------------------------------------------------------------------------------------ | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| 1 | **Engine Dart API** (barrel, `runEngineApp`, `GameModule`/`GameRules`)                    | compile time                              | engine semver — [README](../README.md#versioning--backward-compatibility)                                           |
| 2 | **Engine SQL** (infra migrations + the app-owned hooks)                                    | runtime, vs live DBs + installed binaries | expand/contract — [README](../README.md#versioning--backward-compatibility)                                         |
| 3 | **Game JSONB** (`games.config`, `game_states.state`, `observations.data`, action `p_data`) | in-flight games                           | **game schema version** (below)                                                                                     |
| 4 | **Client caches** (`riverpod.db`, SharedPreferences, image cache)                          | cold-start decode of stale rows           | **`destroyKey` discipline + tolerant decode** (below)                                                               |
| 5 | **Client↔server version**                                                                  | old client meets new backend              | **client-version header + `min_supported_version` gate** (designed; **deferred** — Android uses Play in-app-update) |

**Authority note.** The client `GameRules.isValidAction` is **UX-only** (it
greys out illegal taps); the authoritative rule check is the server hook
`applyAction`. This is what lets many rule changes ship **server-side only**
(see the decision checklist).

### Surface 3 — game schema version (version the game _type_)

A breaking rules/schema change does **not** mutate existing games in place.
Instead each game is **stamped with the schema version it was created under**,
and that version is honored for the game's whole life.

**Where it lives.** A first-class **`games.schema_version` column**
(`INT NOT NULL DEFAULT 1`) — set once at creation (from the client's
`GameModule.latestSchemaVersion`, written by `engine_create_game`) and
immutable. It is kept **out of** the opaque `config`/`state`/observation JSONB
so those payloads stay game-owned and the drain query is a plain column scan.
It is the dispatch key on both sides — the TS harness resolves
`GameModule.versions[schema_version]` (`rulesFor`) around every hook call, the
client resolves `GameModule.versions[schemaVersion]` (`gameRulesProvider`) —
and it is surfaced on the `Game` model (`required int schemaVersion` — the
`NOT NULL` column always provides it). Hooks and engines never receive a
version argument: a `GameRules` unit *is* its version.

**Client gating.** `gameRulesProvider` reads the game's `schemaVersion` and
looks it up in `GameModule.versions` (`supportsSchema` = key membership —
sparse, matching the TS side, so a drained-and-retired old version is
unsupported even though it is lower than the latest). A game created by a
_newer_ build raises `UnsupportedGameSchemaException` rather than mis-parsing
with old code; otherwise everything downstream (engine, content, bots,
seatability) consumes the resolved unit.

**How both sides version.** Neither side branches — each ships another unit:

```ts
// server: _lib/game.ts — one GameRules unit per version
export const gameModule: GameModule = {
  versions: { 1: rulesV1, 2: rulesV2 }, // v1 kept until its games drain
};
```

```dart
// client: game_module.dart — the same keys, client units
@override
Map<int, GameRules> get versions =>
    const {1: MyGameRulesV1(), 2: MyGameRulesV2()};
```

**Retiring an old version — two paths, two lifetimes.** Old code splits in two:

- **Write path** (`applyAction`, `applyLifecycle` — anything that _advances_ state)
  can be retired once **both**: (1) the **drain query** returns zero —
  `SELECT count(*) FROM games WHERE status='active' AND schema_version < N;` —
  and (2) the **force-update floor** has passed the last app version that could
  _create_ that schema. Active games are the only callers of the write path, so
  once they drain it is dead.
- **Read / projection / render path** (`computeObservation` on the server,
  `GameRules.parseObservation` + rendering on the client) must survive **as
  long as you want to replay games created under that schema** — _not_ bounded
  by draining. Replay re-projects every historical `game_states` row through
  `computeObservation` at the game's own `schema_version`, so replays of an old
  finished game stay requestable long after the last active old-schema game
  ended. Retire this path only when you drop replay support for that schema.

In short: **draining gates the write path; replay gates the read path, and
replay outlives draining.** Additive, non-breaking changes do **not** bump the
schema — Surface 3b's decode tolerance absorbs them.

### Surface 3b — decode-tolerance rules (the load-bearing client convention)

Within a single schema version, evolution must be **forward- and
backward-tolerant**: an old client may receive new-shaped JSON, and a new client
may read old-shaped JSON (and old cached rows).

- **New fields must be nullable or `@Default(...)`.** Never add a `required`
  field within an existing schema version.
- **Enums must use `@JsonKey(unknownEnumValue: …)`** (or a sentinel) so an
  unknown value degrades gracefully instead of throwing. Applies to engine
  models too (`GameStatus`, `GameAccess`, `OutcomeResult`, `RelationshipStatus`,
  `ParticipantType` already carry an `unknown` sentinel).
- **Changing a field's type or meaning, or removing it, is breaking** → bump the
  game schema version; do not edit in place.
- These rules apply **identically** to server-response models _and_
  `@JsonPersist` cached models, because cached rows are re-decoded through the
  same `fromJson` on cold start.

### Surface 4 — client caches

On-device state lives in three places: **`riverpod.db`** (the three
`@JsonPersist` providers — `CurrentUserProfile`, `Friendships`,
`PlayerInfoCache`; see §23), **SharedPreferences** (`theme_mode`, `total_wins`,
…), and the **`cached_network_image`** disk cache (avatars bust with
`?v=timestamp`). Discipline:

- **`destroyKey` == the persisted model's schema version, per provider.** Bump
  the _individual_ provider's `destroyKey` when its model's persisted shape
  changes breakingly — do not share one global key, so a profile change does not
  wipe the friendships cache.
- **A cached-row decode failure must be a cache miss** (drop the row, re-fetch),
  never a crash — the safety net when an old row predates a schema bump.
- **SharedPreferences reads must default safely.** If a key's value shape ever
  changes, write under a new key rather than reinterpreting the old one.
- **`deleteUserData` deliberately does not clear `PlayerInfoCache`** — player
  identity is public and survives sign-out by design; the per-provider
  `destroyKey` is its only invalidation lever.

### Surface 5 — client↔server version negotiation (DESIGN ONLY — deferred)

> **Not built.** While Android-only, Play in-app-update handles forced updates
> (see Implementation status #4). This is the blueprint for when the gate is
> reintroduced (iOS/web, or backend-authoritative contraction).

To _contract_ old shapes you must know which client versions are still live and
be able to force the floor up. The design: send `X-Client-Version` (+ platform)
as a global PostgREST header at init; add `min_supported_version` /
`soft_min_version` (per platform) to `private.app_config`, exposed via a
`SECURITY DEFINER` `get_client_requirements(p_platform)` RPC; at startup, block
below the hard floor (Android drives `UpdateNotifier`; iOS/web show a store link
/ reload) and nudge between soft and hard. Keeping the gate platform-agnostic
means iOS/web reuse it unchanged. The floor is what bounds the support window in
Surfaces 2–4: once it passes the last app version that knew an old SQL shape or
game schema, you may _contract_.

### Deploy playbook (expand → ship → contract)

Same as
[README → Versioning & backward
compatibility](../README.md#versioning--backward-compatibility), applied to game
changes:

1. **Expand** — ship the additive DB change (new column / `_v2` RPC / new
   `GameRules` version unit) **before or with** the app release; old shapes
   keep working.
2. **Ship** — the new app creates games at the new schema; old apps keep
   creating/reading the old one against the same DB.
3. **Contract** — retire old code per the two-path rule: the **write path** once
   the drain query is zero **and** the force-update floor has retired old apps;
   the **read/projection/render path** only when you stop supporting replay for
   that schema.

Per-app: vendor with `dart run eigen_engine:sync_supabase`, apply per Supabase
project; migrations are append-only/forward-only (fix forward, never roll back).

### Quick checklist — "I want to change the game"

- Alters the **observation/action/config shape**, or makes in-flight games
  inconsistent/unfair? → **breaking**: ship a new `GameRules` unit on both
  sides (a `v2` folder + `versions` map entry each; new games then create at
  the new key → `games.schema_version`), drain old games, raise the
  force-update floor before contracting.
- Purely additive (new optional field/feature)? → nullable / `@Default`, **no
  bump**; old clients ignore it, new clients default it.
- Server-only rule logic, same shapes, in-flight games stay consistent? → change
  `applyAction` only, **no bump**.
- New enum value? → ensure `unknownEnumValue` tolerance is already shipped, then
  expand/contract.
- Touching a persisted model's shape? → bump **that provider's** `destroyKey`.

### Implementation status (built)

Three of the four foundations are implemented (dev-phase, in-place); the version
gate (Surface 5) is **designed but deliberately not built**.

1. **Game schema version** — `games.schema_version` column; `engine_create_game`
   stores it from `GameModule.latestSchemaVersion`; the dispatch key for the
   per-version `GameRules` units on both sides (`rulesFor` in the TS harness,
   `gameRulesProvider` on the client); surfaced on `Game` and gated by
   `GameModule.supportsSchema` (key membership) in `gameRulesProvider` (render
   path).
   **Join is gated too:** `app_join_game`/`app_join_game_by_code` take the
   client's max supported schema and refuse to seat the caller in a newer-schema
   game, so every join path (lobby, friends, by-code, deep link) is blocked
   _before_ a participant row is created — not only when the game screen later
   tries to render. The lobby also disables the Join button for unsupported
   games as immediate feedback.
2. **Decode tolerance** — `unknown` sentinel + `@JsonKey(unknownEnumValue:)` on
   the wire enums (`GameStatus`, `GameAccess`, `OutcomeResult`,
   `RelationshipStatus`, `ParticipantType`). Guarded by
   `test/core/decode_tolerance_test.dart`.
3. **Cache discipline** — each `@JsonPersist` provider documents its
   per-provider `destroyKey` bump rule; decode-failure is a safe cache-miss
   (riverpod core); `PlayerInfoCache` intentionally survives sign-out.
4. **Version gate (Surface 5) — DEFERRED.** While Android-only, forced updates
   are handled by Play in-app-update (immediate priority) via the existing
   `UpdateNotifier`, so a server-side gate would guard nothing yet.
   **Re-introduce when any of:** (a) iOS or web ships (no Play in-app-update
   equivalent); (b) you need backend-authoritative "who's live?" before a risky
   contraction; (c) you want telemetry of live client versions. Until then, the
   force-update floor on Android is Play-driven, not a server gate — "is it safe
   to contract?" is judged from Play Console adoption rather than backend
   telemetry.

---

## 25. Anonymous (Guest) Auth

To reduce the friction of trying the app, a visitor can tap **Play as guest** on
the login screen and start playing immediately on a real Supabase **anonymous**
session — no Google account required. Anonymous users are full
`authenticated`-role JWTs, so existing RLS policies and RPC grants apply to them
unchanged; the only differences are provisioning, a capped capability set, and a
later upgrade path.

### Provisioning

`signInAnonymously()` creates an `auth.users` row with a **null email** and the
`is_anonymous` claim set. The `handle_new_user` trigger detects the null email
and assigns a generated `player_NNNNN` handle (rather than deriving from the
email); `handle_new_user_profile` defaults the profile `display_name` to that
handle with no avatar. `users.email` is nullable specifically to allow this.

### Capability scope — play only

Guests can play (including creating **public, unrated** games) but cannot use
rated games or social features. Because anonymous users share the
`authenticated` Postgres role, this cannot be enforced with `GRANT`/`REVOKE` —
it is a **runtime check on the `is_anonymous` JWT claim**, applied at whichever
layer owns the operation:

- **Edge-function routes** read the caller's guest status from the JWT and gate
  in TypeScript: `game/create` blocks `friends` access for guests and
  **rejects** a guest's `rated = true` (the `rated` assertion is validated, not
  coerced — §5/§8); `game/create-solo` allows guests local bots only;
  `game/add-bot` rejects guests; the `social/*` routes reject a guest
  **caller**.
- **Client-direct RPCs** keep their guest gate in SQL (no EF in the loop):
  `app_join_game` raises if a guest tries to join a **rated** game (also covers
  `app_join_game_by_code`) — otherwise a guest would gain a `player_ratings` row
  and skew opponents' ratings; `app_search_users` is **registered-only**
  (`private.require_permanent_user()`).
- **Target** anonymity stays in SQL because it needs the target's row, not the
  caller's JWT: `private.is_anonymous_user(uuid)` makes `app_search_users`
  exclude anonymous accounts and `engine_send_friend_request` reject an
  anonymous target — so a throwaway guest never appears in or receives friend
  activity.

Client-side, the `isAnonymousProvider` (derived from the auth stream) drives UI
gating: the Social drawer destination stays visible but is **disabled**
(`NavigationDrawerDestination.enabled = false`) for guests — and `/social` is
still redirected home in the router as a deep-link backstop — the rated toggle
is hidden in the New Game dialog, and Settings shows a "Save your progress"
upgrade card. Rated games also still appear in the lobby for guests with a
disabled join button ("Sign up to play rated"). This visible-but-disabled
treatment mirrors what the lobby already does for schema-unsupported games.
These are UX only — the server checks above are the authoritative boundary.

### Upgrade (guest → permanent Google account)

`AuthController.upgradeToGoogle()` runs the native Google sheet and calls
`linkIdentityWithIdToken` (requires manual linking enabled in Supabase). On
success the **`auth.users.id` is preserved**, so all of the guest's games,
ratings, and friendships carry over with no data migration. Conversion is an
_UPDATE_ to `auth.users` (not an insert), so the insert-only `handle_new_user`
trigger never fires — instead `on_auth_user_converted` (an `AFTER UPDATE`
trigger gated on `is_anonymous` flipping true→false) runs
`handle_user_conversion` to backfill `users.email` and **overwrite**
`user_profiles.display_name` / `avatar_url` from the Google OAuth metadata. The
username is kept as the stable handle. The client then invalidates
`currentUserProfileProvider` and `playerInfoCacheProvider(id)` so the new
identity surfaces immediately.

If the chosen Google account already belongs to a registered user, the link
fails with `identity_already_exists`; the service throws
`AccountExistsException` and the controller **switches into the existing
account** instead — clearing the abandoned guest's local data and FCM token
(mirroring `signOut`) and signing in normally. The guest's orphaned anonymous
row is reclaimed by the cleanup job.

### Cleanup

`private.cleanup_stale_anonymous_users()` (daily pg_cron,
`cleanup-stale-anon-users`) deletes anonymous accounts older than 7 days with no
game action in the last 2 days. The short windows keep guest data from
accumulating long enough that deletion is a painful surprise; active guests are
always kept, and the in-app guest upgrade card warns about the window. Each is
torn down through `engine_purge_user` — the **same** path the
`game/delete-account` route uses (forfeit active games first, then cancel
created lobbies, leave joined lobbies, and delete the `auth.users` row,
cascading as in §22). Because the teardown is shared, a guest's lingering games
are resolved gracefully rather than orphaned, so a delete never leaves a null
creator or ghost participant — no separate live-game guard is needed. Each
guest's purge runs in its own subtransaction so one failing game can't block the
rest of the batch.

### Configuration

`config.toml` requires `enable_anonymous_sign_ins = true` and
`enable_manual_linking = true`; the same two settings must be enabled in the
production Supabase dashboard. No `additional_redirect_urls` / deep-link change
is needed — `linkIdentityWithIdToken` uses the native Google sheet, not a
browser redirect.

---

## 26. Bots — Execution & Authentication

A bot is the same pure function the engine already drives for humans —
**observation → legal action** — so everything downstream (`submit_*_action` →
`commit_action` → `finish_game` → fan-out → ratings) is reused unchanged. The
engine ships **no bot logic**; it provides the seats a bot plugs into and a
stable contract. Adding a bot is a hand `INSERT` into the `bots` table (rare,
one-time — there is no provisioning RPC). This section is the **architecture and
security model**; the implementor how-to (the `LocalBot` Dart contract, the
reference server, action-data design) lives in the **Game Implementation Guide →
Adding Bots**.

> **Non-goal: offline play.** "Local bot" means _where the move is computed_,
> not _offline_. The engine is **server-authoritative** — every transition runs
> in `applyAction`, observations are computed server-side, and
> identity/outcomes/ratings live in the DB. A local-bot game still needs the
> server for _every_ move (the client picks the move; the server validates,
> applies, and fans out). True offline solo is a separate, out-of-scope feature
> — it would mean reimplementing the authoritative rules on-device.

### Two execution models, one spine

|              | **Local bot** (`is_local = true`)                | **Server bot** (`is_local = false`)                    |
| ------------ | ------------------------------------------------ | ------------------------------------------------------ |
| Who computes | the sole human's own client                      | a remote endpoint the operator runs                    |
| Wake         | the client's existing observation Realtime sub   | EF `fetch` to `webhook_url` (HMAC-signed)              |
| Action entry | `game/local-bot-action` route (authenticated)    | `bot/action` route (anon; per-bot HMAC)                |
| Use case     | solo play, incl. hidden-info (no human to cheat) | multiplayer fill, rated games, "play while app closed" |

Both write **observation rows** like humans (the `observations` table is
generalised — nullable `user_id`, plus `bot_id` and `player_index`; see §2), so
a server bot's wake falls out of the EF's post-commit `notifyTransition` (§20)
and arrives **with the observation** — no pull or compute-on-demand call.

### Authorization invariants (engine-enforced, not per-game)

A local bot's move is **computed and submitted by a human's client**, which is
untrusted: you cannot prove a client-computed move came from the bot's logic
rather than a human cherry-picking it (verifying it would mean running the bot's
policy server-side — i.e. making it a server bot). Three invariants follow,
enforced structurally by _which_ function may seat a bot:

1. **Local bot ⇒ exactly one human.** Two independent reasons, so it holds even
   for a perfect-information unrated game: _information_ — the driving client is
   handed the bot's secret view, which it must not learn if an opponent could
   exploit it; _provenance/collusion_ — a local bot is an extra seat one human
   secretly controls, masquerading as neutral AI to the others.
2. **2+ humans ⇒ server bots only** (corollary of 1).
3. **Rated ⇒ server bots only, no guests** — a rated result needs trusted move
   provenance.

A fourth, **timing** invariant partitions the bot class in a solo game: **local
⇒ untimed, server ⇒ timed.** A turn deadline is a liveness backstop only a
possibly-unreachable server bot needs; a local bot is driven by the present
human's client and must not lose a turn because the human navigated away (this
is also why local + server can't mix — one class per game). The "create a rated
game

- a local bot, then let a human join and cheat" scenario is thus **impossible by
  construction**.

### Seating — two paths

Each path enforces one slice of the invariants (see §5 for signatures):

- **`game/create-solo` (→ `engine_create_solo_game`)** — the solo constructor,
  generalised to N bots. The route validates bot class/timing/schema policy in
  TS (§5); the RPC creates the game with the caller as the **sole** human,
  **forced unrated**, seats everyone, and flips to `ready` **in one shot**.
  Because the game is never joinable, no second human can ever enter — invariant
  1 holds with no extra guard. Anonymous callers may seat **local bots only**
  (server bots cost real per-move compute).
- **`game/add-bot` (→ `engine_add_bot_to_game`)** — creator-only waiting-room
  fill (the host's "Add bot" button). The route rejects guests in TS; the RPC,
  under its seat-count `FOR UPDATE`, rejects local bots (invariant 2), a
  schema/config-incompatible bot, and a non-`rated_eligible` bot in a rated game
  (invariant 3, never downgraded). The seat/guard logic is factored into
  `private.seat_server_bot` so the **deferred** matchmaking auto-fill can reuse
  it via service-role without the creator check.

So local bots are reachable **only** via `game/create-solo`; no code path places
one into a rated or multi-human game.

### Wake & action entry

- **Server bot.** Woken post-commit by `notifyTransition` → `wakeBot` `fetch`es
  the seat's observation to `webhook_url` (HMAC `x-wake-signature`; see §20).
  The bot replies on the **`bot/action`** route (anon; HMAC-gated). One wake,
  two transports; the timeout commit is the liveness backstop for an unreachable
  bot (hence server ⇒ timed).
- **Local bot.** A device can't receive a webhook and must not hold a secret, so
  it uses what the client already has: its own observation Realtime sub carries
  `pending_players`. When a bot seat in a **solo** game goes pending, the client
  pulls that seat's full view via **`app_local_bot_observation`** (gated) and
  submits via the **`game/local-bot-action`** route (see _Local-bot driving_).

Both action paths commit through `engine_commit_action` (same `FOR UPDATE`,
version, deadline, "is it this seat's turn?" checks; same `applyAction → commit`
with `'bot'` type) — they differ only in who may call and how the seat is
authorized.

### Config-based availability

`schema_version` gates the observation/action **shape**; a separate axis is
whether a bot supports the **rules variant** chosen in `games.config` (e.g. a
chess bot that does standard but not misère — same schema). That capability is
declared in **`bots.config`** and interpreted by the game's
**`botSeatable(bot_config, game_config)`** hook (§4, default `true`) — the
**single source of truth**: enforced at seating in the EF and mirrored to the
pickers by the Dart `botSeatable` twin (§5), so the rule is never duplicated by
hand and retuning the predicate ships in the rules module, not an app release.

### Local-bot driving (client-side)

A local bot has no server runtime — its Dart `LocalBot` runs on the **sole
human's client**. A bot is a pure reducer
`(observation, state) → (action,
nextState)`; the engine runs `chooseAction` in
an **ephemeral isolate** (`Isolate.run`), so a move may take seconds without
ever blocking a UI frame and the implementor writes no isolate code. The flip
side — the bot and engine are copied into the isolate per move — is why a bot
needing large static data (a pretrained net) belongs **server-side**, not local;
everything the call touches must be isolate-sendable.

Two providers cooperate (`local_bot_driver.dart`): a **supervisor**
(`LocalBotDriver`, a `void`-state provider the game screen keeps alive)
evaluates the **solo gate once** (exactly one human) and watches one **per-seat
driver** (`LocalBotSeatDriver`) for each bot seat with a shipped `localBots`
impl — server-bot seats (no match) are skipped, their webhook drives them. Each
per-seat driver holds that seat's committed state on the main isolate and,
whenever the seat is pending, pulls its view via `app_local_bot_observation`
(sole-human-gated), runs `chooseAction` off-thread, and submits through the
`game/local-bot-action` route.

Keeping the committed state in the driver (not inside the compute) makes
preemption free: a newer observation just spawns a fresh compute and the doomed
one is **discarded** — it was computed on an older game version than the
stream's latest (the orphaned isolate finishes and is GC'd); state is committed
**only when its action is accepted**. Each seat is an independent entity, so a
simultaneous-pending game (e.g. Exploding Kittens "Nope") drives all its bot
seats in parallel and the server's version lock arbitrates who landed first. The
server re-validates every move under lock, so a stale or duplicated submit is
harmless — the driver is an optimisation of "who computes", never a trust
boundary.

The driver is **screen-scoped**: leave and it disposes; re-enter and it resumes
from the current observation (re-seeding state via `createState`). Liveness is
covered without it — an untimed abandoned solo game is reaped by idle-cleanup;
"keep playing while the app is closed" is, by definition, a _server_ bot. This
is also why local bots must be **untimed**: nothing drives them while the client
is away. The `LocalBot` reducer contract (pure, commit-on-accept,
isolate-sendable) and a stateful-bot example are in the Game Implementation
Guide → Adding Bots.

### One identity, many seats

A single `bots` row may occupy several seats of one game (e.g. one `poker_ai`
filling four seats of a 6-player game). Seats are addressed by
`(game_id,
player_index)`, never by `bot_id`: each seat has its own observation
row and its own wake carrying that seat's `player_index`, the bot echoes it in
the signed action, and the `bot/action` route acts on exactly that seat. Seats
are fully independent `observation → action` calls — one never sees another's
hidden state — and ratings treat each as an independent result for the identity
(never rated against its own other seats; see §8).

Conversely, **many personas can share one implementation** (N:1): point several
`bots` rows at the same `webhook_url` (server) or register several configured
instances of one `LocalBot` class (local), each with a distinct `username` and
`config`. Identity (`username`/`id`) _names_ the persona; `bots.config`
_parameterizes_ it — so one implementation backs many separately-rated personas
with no code change and no behaviour-classifier column. A server wake carries
`username` and `config`, letting one deployment self-configure per persona.

### Authentication — one derived per-bot HMAC, both directions

Both directions authenticate with a **per-bot key derived in the edge function**
as `HMAC(BOT_SIGNING_SECRET, bot_id)` (`_engine/bot_auth.ts`). No per-bot secret
is stored — not on the `bots` row, not in Vault; only the single master
`BOT_SIGNING_SECRET` function secret exists, and the per-bot key falls out of it
deterministically. The **action is the only security boundary**; the wake is
low-stakes because every move is re-validated against authoritative state under
the `games FOR UPDATE` lock.

A signature is `"v1," + base64(HMAC-SHA256(derivedKey, "<domain>:<message>"))`:
the signed bytes carry a **domain tag** (`wake` / `action`), and the `v1,`
prefix names the scheme so it can evolve (Standard-Webhooks style — a future
`v2,` can be verified side-by-side during a migration window).

- **bot → us (action).** The bot HMAC-SHA256s `"action:" +` the exact JSON
  `{game_id, bot_id, player_index, version, data}` it sends, with its derived
  key. The anon `bot/action` route verifies the MAC
  (`verifyBotSignature`, via `crypto.subtle.verify` — constant-time) before
  committing the move via `engine_commit_action`. This authenticates both the
  actor and the move bytes; replay is handled by the version check +
  pending-seat re-check under lock (a resubmitted action carries a stale
  version).
- **us → bot (wake).** `wakeBot` HMAC-SHA256s `"wake:" +` the exact JSON body
  with the same derived key and sends the `v1,`-prefixed base64 in
  `x-wake-signature`; the bot recomputes over the raw body and compares. A leak
  forges wakes to that one bot only — wasted compute, no game effect.

One key signs both directions; the signed **domain tag** is what keeps them
apart — a MAC captured from one direction can never verify in the other. The
trade for HMAC over an asymmetric signature is that the platform holds a
secret that could forge this bot's moves — fine for first-party bots (a full DB
compromise can write `game_states` directly anyway). The signed wake body is the
exact bytes the EF sends, so the bot verifies without re-serialising.

### Hidden-information local bots

The constraint on a local bot is **not** "perfect information" — it is "**is
there a human to cheat against?**" In a solo game (one human, the rest bots)
there is none, so peeking at a bot's hidden state only spoils the player's own
unrated game, exactly like a single-player offline engine. Thus: perfect-info
any roster → local OK; **hidden-info, solo, unrated → local OK** (e.g.
Stratego); hidden-info **with human opponents** → server only.
`app_local_bot_observation` is the one place the engine reveals a bot's full
view to a client, and its gate (caller is the sole human; target is a local bot
in this game) is what makes that safe.

### Solo play UX — derived, not declared

The solo picker is a first-class one-tap entry, derived entirely from data — no
`SoloPlaySpec`. It is **shown** iff a playable _(timing, bot-class)_ combination
exists (`soloPlayAvailableProvider`), honouring the partition: an untimed mode
with a usable local bot, or a timed mode with a usable server bot (never to
guests). Opponent **counts** come from the game's existing `playersForConfig` /
`buildCreationConfig`; **opponents** are the usable bots' `display_name`s (these
are _personas_, not a difficulty ladder, so the copy says "choose your
opponent"). Switching timing re-derives the usable list, so no invalid
combination can reach `game/create-solo`. The other touchpoint is the host's
waiting-room **"Add bot"** affordance for a multiplayer human game (offers only
`rated_eligible` bots when the game is rated; hidden for guest hosts).

### Versioning bot logic

Both kinds reuse the **schema gate** from different "highest supported schema"
sources — no separate bot-versioning machinery. **Local:** the logic ships in
the app build, so a build may drive a local bot iff
`module.schemaVersion >=
game.schema_version` **and** `localBots` contains that
`username` — an old build simply doesn't offer it. **Server:** the logic lives
in the operator's deployment, versioned independently; the `bots.schema_version`
row gates which game schemas it may be seated into.

### Operator setup (server bot)

```sql
insert into bots (username, display_name, schema_version,
                  is_local, webhook_url, rated_eligible)
values ('hard_ai', 'Hard AI', 1,
        false, 'https://my-bot.example/wake', false)
returning id;  -- → <bot_id>
```

No per-bot secret is stored. The bot deployment derives its **HMAC key** the
same way the edge function does — `HMAC-SHA256(BOT_SIGNING_SECRET, <bot_id>)` —
and uses it to sign actions and verify wakes. Only the platform's single
`BOT_SIGNING_SECRET` function secret needs provisioning. A local bot needs no
key — just an `is_local` row whose `username` matches a `GameRules.localBots`
entry.
