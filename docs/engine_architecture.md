# Eigen Engine — System Design

## 1. Vision & Architecture

The goal is to build a **reusable "whitelabel" game engine**. Each app instance runs exactly **one** game (e.g., "Strategy Chess", "Strategy Poker"), but the underlying `core` codebase is identical.

### Architectural Separation

- **Core Engine (The "Framework")**: Auth, user management, game networking, rating system, settings. Owns the `users`, `games`, `game_states`, `observations`, `participants`, `actions`, and `game_outcomes` tables plus all infra RPC functions.
- **Game Module (The "Implementation")**: The specific rules, board rendering, and action validation for this specific app. Communicates with infra through five SQL hooks (`game_initial_state`, `game_apply_action`, `game_compute_observation`, plus optional `game_rating_pool` and `game_handle_system_action`) and one Dart `GameModule`.

---

## 2. Database Design

### Tables

#### `users` (System/Immutable)
- `id` (uuid, PK, references auth.users)
- `username` (text, unique)
- `email` (text)
- `payment_tier` (text, default 'free')
- `created_at`, `updated_at`

#### `user_profiles` (User Editable)
- `id` (uuid, PK, fk to users)
- `display_name` (text)
- `avatar_url` (text)
- `updated_at`

#### `games` (Game Metadata)
- `id` (uuid, PK)
- `created_by` (uuid, nullable fk to users, **ON DELETE SET NULL**) — the host; SET NULL when the account is deleted (the game row is preserved)
- `status` (enum: `waiting`, `ready`, `active`, `finished`, `aborted`)
- `access` (enum: `public`, `private`, `friends`)
- `turn_seconds` (int, nullable) — per-action timer mode: each turn gets a fresh N seconds. Null means no per-action timer. **Mutually exclusive with `budget_seconds`.**
- `budget_seconds` (int, nullable) — accumulated clock mode: each player has a personal time bank of N seconds that drains while they are acting. Null means no bank. **Mutually exclusive with `turn_seconds`.** See §3 for the sequential-only constraint.
- `increment_seconds` (int, nullable) — Fischer increment: seconds added to the acting player's bank after each bank-consuming action. Only valid when `budget_seconds IS NOT NULL`. Null treated as 0.
- `min_players` (int, default 2) — minimum participants required to transition the game to `ready` status. The host can start once this threshold is met.
- `max_players` (int, default 2) — maximum participants allowed to join. `join_game` rejects once this is reached.
- `config` (jsonb) — game-specific configuration passed through to the three game hooks. Infra never reads this.
- `rated` (boolean, default false) — true if this game affects player ratings. Set by `create_game` server-side via `private.game_rating_pool()`; the client only sends a preference boolean.
- `rating_pool` (text, nullable) — the pool this game's results will be counted in (e.g. `'rapid'`, `'daily'`). Always `NULL` when `rated = false`. Derived by the server; clients cannot forge it.
- `short_code` (varchar(6), unique, not null) — human-readable join code generated at game creation. Used by `join_game_by_code` for invite-by-code joining. Generated via `upper(substring(md5(random()::text) from 1 for 6))` with a retry loop on unique violations. Always set — `create_game` loops until a unique code is found.
- `created_at`, `finished_at`, `updated_at`
- **Constraints**: `turn_seconds IS NULL OR budget_seconds IS NULL` (timing mode exclusive); `increment_seconds IS NULL OR budget_seconds IS NOT NULL` (increment requires budget); `min_players >= 1 AND max_players >= min_players`; `NOT rated OR rating_pool IS NOT NULL` (if rated, pool must be set).

#### `game_outcomes` (Per-Player Results — Service Role Only Writes)
- `game_id` (uuid, fk to games, PK composite)
- `player_index` (int, PK composite) — 0-based player slot
- `user_id` (uuid, nullable fk to users, **ON DELETE SET NULL**) — null for bots; SET NULL when the account is deleted so the outcome row is preserved for analytics and replay attribution
- `bot_id` (uuid, nullable fk to bots) — null for humans
- `result` (text, CHECK: `win`, `loss`, `draw`, `eliminated`)
- `score` (numeric, nullable) — raw game score; optional, for display or future score-based variants
- `placement` (int, NOT NULL) — ordinal finish rank (1 = best); ties share the same value. Passed directly to OpenSkill as the rank input. See §8.
- `team_index` (int, NOT NULL) — groups players into rating teams. Players sharing a value are rated together. Use `player_index` for individual games (each player is their own team of one); teammates share a value for team games (e.g. Literature, Canadian Fish). See §8.
- **Identity constraint**: `NOT (user_id IS NOT NULL AND bot_id IS NOT NULL)` — at most one identity is set. Both may be NULL when the human player's account was deleted after the game finished. `player_index` is always preserved and is the authoritative attribution key.

A scalar winner column can't express team wins (Literature), multiple placements (Poker), or mid-game eliminations. One row per participant handles all of these.

#### `game_states` (Append-Only State History — Service Role Only)

One row is INSERTed per state transition; rows are never UPDATEd. Current state = `ORDER BY version DESC LIMIT 1`. The full history enables zero-compute replay via `get_replay` — no action log re-execution needed.

- `game_id` (uuid, fk to games, composite PK with `version`)
- `version` (int, composite PK) — monotonically incrementing counter starting at 0 (initial state). Used for optimistic locking. Mirrored to every `observations` row.
- `state` (jsonb) — pure game payload: board, deck, fog map, etc. Does **not** carry whose-turn or winner info — those are first-class infra columns.
- `pending_players` (int[]) — 0-based indices allowed to act now. Singleton for sequential games; full set for any-player games; empty when no one may act (game over / paused). Stored here (not only in observations) so `get_replay` can call `game_compute_observation` for each historical row without re-running game logic.
- `rng_seed` (bigint) — xorshift64 PRNG seed. Advanced inside `game_apply_action`. Never exposed to clients. Must be non-zero.
- `turn_deadline` (timestamptz, nullable) — absolute deadline for the current pending player(s). Set by infra after every action using the timing precedence chain (see §3). Null for untimed games. Used by `submit_action` (expiry guard) and `expire_turn` (cron).
- `player_times` (bigint[], nullable) — remaining bank in **milliseconds** per player, 1-indexed (`player_times[player_index + 1]`). Null for non-budget games. Infra-owned: updated on every bank-consuming action.
- `turn_started_at` (timestamptz, nullable) — timestamp when the current turn began, set to transaction time after every action. Used by `submit_action` to compute elapsed time for bank deduction. Null for untimed games.
- `created_at` — when this version was committed. Useful for audit and replay timeline.
- **RLS**: No policies — service role only.
- **Indexes**: `(game_id, version DESC)` covers current-state lookup and `expire_all_turns` DISTINCT ON. Partial index on `turn_deadline WHERE NOT NULL` for the cron sweep.

#### `observations` (Player-Specific Projections)
- `game_id`, `user_id` (PK composite)
- `data` (jsonb) — game-specific state slice computed by `game_compute_observation`. Perfect-info games see the full state; hidden-info games see only their permitted slice.
- `pending_players` (int[]) — per-player pending array. For perfect-info games mirrors `game_states.pending_players`; hidden-info games may narrow it (e.g. Exploding Kittens Nope window).
- `version` (int) — mirror of `game_states.version`. Clients pass this back as the optimistic lock key on `submit_action`.
- `turn_deadline` (timestamptz, nullable) — mirror of `game_states.turn_deadline`. Clients use this to display countdown timers without a separate query.
- `player_times` (bigint[], nullable) — mirror of `game_states.player_times`. Clients use this to display per-player accumulated clock budgets.
- `turn_started_at` (timestamptz, nullable) — mirror of `game_states.turn_started_at`. Combined with `player_times`, clients animate the active player's live countdown without polling: `remaining = player_times[myIndex] - elapsed_since(turn_started_at)`.
- `created_at`, `updated_at`
- **Realtime**: enabled. Game screen subscribes by `game_id`; home screen uses fetch-on-enter + pull-to-refresh.
- **RLS**: Users see only their own row (`user_id = auth.uid()`).

#### `participants`
- `id` (uuid, PK)
- `game_id` (uuid, fk, ON DELETE CASCADE)
- `user_id` (uuid, nullable fk to users, **ON DELETE SET NULL**) — null for bot participants; SET NULL when the account is deleted so the seat row is preserved for `gamePlayersProvider` and replay participant counts
- `bot_id` (uuid, nullable fk to bots) — null for human participants; both `user_id` and `bot_id` can be null simultaneously when the account was deleted after the game finished
- `player_index` (int) — 0-based seat (authoritative seat attribution key)
- `type` (participant_type, default 'human')
- `created_at`
- **Unique**: `(game_id, user_id)` where `user_id IS NOT NULL`; `(game_id, player_index)`
- **Identity constraint**: `NOT (user_id IS NOT NULL AND bot_id IS NOT NULL)` — at most one identity is set. Both may be NULL after account deletion on a finished game. `delete_account` explicitly removes the participant row for waiting/ready games (via `cancel_game` / `leave_game`) so this null state only ever occurs on finished games.

#### `actions` (Audit Log — Service Role Only)
- `id` (uuid, PK)
- `game_id` (uuid, fk, ON DELETE CASCADE)
- `user_id` (uuid, nullable fk to users, **ON DELETE SET NULL**) — set for human actions; null for bot/system actions; SET NULL when account is deleted (the action row is preserved for the audit log)
- `bot_id` (uuid, nullable fk to bots) — set for bot actions; null for human/system actions
- `type` (enum: `user`, `bot`, `system`)
- **Constraint** `actions_identity_check`: `user` → `bot_id IS NULL` (user_id may be null after deletion); `bot` → `bot_id NOT NULL, user_id NULL`; `system` → at most one identity (forfeit carries the initiating player's id; timeout/auto_forfeit carry neither)
- `data` (jsonb)
- `player_index` (int, nullable) — **denormalized seat index of the acting player**, written at commit time from the participant row. Survives user deletion. Used by `get_replay` to attribute each action to a seat without joining `participants`. NULL only for anonymous system actions (timeout, auto_forfeit) where no single player initiated the event; forfeits always carry the forfeiting player's index.
- `version_after` (int, NOT NULL) — the `game_states.version` produced by this action. Links each action to its resulting state snapshot; `WHERE version_after = N` joins the action to the row it created.
- `created_at`

#### `relationships` (Friends)
- `id` (uuid, PK)
- `user_id_1`, `user_id_2` (fk, canonical order: `user_id_1 < user_id_2`, `ON DELETE CASCADE`)
- `initiated_by` (fk to users, `ON DELETE CASCADE`)
- `status` (enum: `pending`, `accepted`, `blocked`)
- `created_at`, `updated_at`
- **Unique**: `(user_id_1, user_id_2)`
- **Indexes**: `user_id_1`, `user_id_2`, `status`
- **RLS**: `SELECT` for authenticated users where `auth.uid() IN (user_id_1, user_id_2)`. All mutations go through `SECURITY DEFINER` RPCs.
- **Realtime**: enabled.

#### `bots` (Bot Player Registry)
- `id` (uuid, PK)
- `username` (text, unique) — short handle (e.g. `'easy_ai'`), displayed like a player username
- `display_name` (text) — human-readable name (e.g. `'Easy AI'`)
- `avatar_url` (text, nullable) — bot avatar
- `bot_type` (text) — internal classifier for the bot logic (e.g. `'easy_ai'`, `'random'`)
- `game_type` (text, nullable) — game this bot is scoped to; `NULL` means game-agnostic
- `created_at`
- **RLS**: any authenticated user can read (`SELECT TO authenticated USING (true)`). Write is service role only.

#### `player_ratings` (Per-Player Per-Pool OpenSkill Rating)
- `id` (uuid, PK)
- `user_id` (uuid, nullable fk to users, ON DELETE CASCADE)
- `bot_id` (uuid, nullable fk to bots, ON DELETE CASCADE)
- `pool` (text) — rating pool name (e.g. `'rapid'`, `'daily'`)
- `mu` (double precision, default 25.0) — OpenSkill mean skill estimate
- `sigma` (double precision, default 25.0 / 3.0) — OpenSkill uncertainty
- `display_rating` (int, default 0) — `max(0, round((mu - 3 × sigma) × 40))`. Denormalised for cheap leaderboard queries.
- `created_at`, `updated_at`
- **XOR constraint**: `(user_id IS NULL) != (bot_id IS NULL)`
- **Unique indexes**: `(user_id, pool)` where `user_id IS NOT NULL`; `(bot_id, pool)` where `bot_id IS NOT NULL`
- **RLS**: any authenticated user can read. Writes are service role only (upserted by the `update-ratings` edge function).

Display rating formula — new player (mu=25, sigma=25/3 ≈ 8.33): display ≈ 0. Established player (mu=30, sigma=2): display ≈ 960.

#### `rating_history` (Immutable Per-Game Rating Audit Log)
- `id` (uuid, PK)
- `user_id` (uuid, nullable fk to users, ON DELETE CASCADE)
- `bot_id` (uuid, nullable fk to bots, ON DELETE CASCADE)
- `game_id` (uuid, fk to games, ON DELETE CASCADE)
- `pool` (text)
- `mu_before`, `sigma_before` (double precision) — rating snapshot before this game
- `display_before` (int)
- `mu_after`, `sigma_after` (double precision) — rating snapshot after this game
- `display_after` (int)
- `display_change` (int) — signed delta (`display_after - display_before`)
- `created_at`
- **XOR constraint**: `(user_id IS NULL) != (bot_id IS NULL)`
- **Indexes**: `(user_id, pool, created_at DESC)` where `user_id IS NOT NULL`; `(game_id)`
- **RLS**: authenticated users can only read their own history (`user_id = auth.uid()`). Bot history is not readable by clients.

#### `private.app_config` (Environment Configuration)
- `key` (text, PK) — config key (e.g. `'serverless_base_url'`)
- `value` (text, NOT NULL) — config value
- `description` (text, nullable)
- `updated_at` (timestamptz)
- **Scope**: `private` schema — not exposed via the REST API. Read by `SECURITY DEFINER` trigger functions only. Sensitive values (secrets) belong in Vault, not here.
- **Local dev**: seeded via `seed.sql`. Production values are inserted via the Supabase dashboard or a deploy script.

### Views

**`friends_view`** is the only view in the public schema (see below). The former `public_players` view has been replaced by the `get_players` RPC — see §7.

### `get_players` RPC

**`public.get_players(p_ids uuid[])`** — unified identity lookup for both humans and bots:

```sql
CREATE FUNCTION public.get_players(p_ids UUID[])
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

REVOKE EXECUTE ON FUNCTION public.get_players(UUID[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_players(UUID[]) TO authenticated;
```

**Why a function, not a view?** The Supabase linter flags `SECURITY DEFINER` views in the `public` schema. A `SECURITY DEFINER` function achieves the same privilege bypass without the linter warning, because `SECURITY DEFINER` on a function is the documented pattern for cross-user identity lookups. `REVOKE EXECUTE FROM PUBLIC, anon` + explicit `GRANT TO authenticated` locks down access.

**Scope: game-level identity only.** Returns only public-safe columns (no email, no payment_tier). `display_name` is non-null in both branches. Cached per-ID on the client via `playerInfoCacheProvider(id)` — `keepAlive: true` + SQLite persistence via `@JsonPersist()`. See §23.

> **Social features do not use this RPC.** Friend requests, user search, and relationship management are human-only. Those features query `users` and `user_profiles` directly so bots never appear in search results or friend lists.

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
The view is scoped to `auth.uid()` at definition time, so a simple `SELECT * FROM friends_view WHERE status = 'accepted'` returns only the caller's accepted friends. Realtime subscriptions must use the base `relationships` table.

### Search Indexes

Trigram indexes (`pg_trgm`) are enabled for fuzzy user search:
- `users_username_trgm_idx` — GiST trigram index on `users.username`
- `user_profiles_display_name_trgm_idx` — GiST trigram index on `user_profiles.display_name`

These power the `search_users` RPC's `ILIKE` queries efficiently.

---

## 3. Timing System

Timing is **infra-owned** — the three game hooks never implement clock logic. Infra reads the timing columns from `games`, applies the precedence chain, and writes `turn_deadline`, `player_times`, and `turn_started_at` after every action.

### Timing Modes

| Mode | Columns set | Behaviour |
|------|-------------|-----------|
| **Untimed** | both null | No deadline. Players act at any pace. |
| **Per-action** | `turn_seconds = N` | Each turn gets a fresh N-second window, regardless of history. |
| **Accumulated clock** | `budget_seconds = B`, optionally `increment_seconds = I` | Each player has a personal bank of B seconds. The bank drains while that player is acting. I seconds are added to the acting player's bank after each bank-consuming action (Fischer increment). |

These modes are mutually exclusive at the schema level. A `CHECK` constraint prevents both `turn_seconds` and `budget_seconds` from being set simultaneously.

### Per-Action Action Override

Any game hook may return `"turn_seconds": N` in its response envelope to override the deadline for **that specific action only**, without touching any player's bank. This is for situations where a particular action phase has its own fixed window (e.g. a 10-second Nope window in Exploding Kittens, a pre-flop betting timer in Poker). The hook returning `turn_seconds` is the only way for game logic to influence timing — all other clock management is fully infra-owned.

### Deadline Precedence Chain

Applied in `submit_action`, `start_game`, and `expire_turn` after every state change:

```
1. Game is over (outcome ≠ null)  →  deadline = NULL, turn_started_at = NULL
2. Hook returned turn_seconds N   →  deadline = NOW() + N seconds (bank untouched)
3. Budget mode (budget_seconds ≠ null), next player has remaining bank B  →  deadline = NOW() + B ms / 1000
4. Per-action mode (turn_seconds ≠ null)  →  deadline = NOW() + turn_seconds
5. Untimed  →  deadline = NULL
```

### Bank Deduction (Budget Mode)

On every `submit_action` where the hook did **not** return `turn_seconds`:

1. Compute `elapsed_ms = NOW() - turn_started_at` (transaction time — consistent within the call).
2. Deduct `elapsed_ms` from the acting player's bank (`player_times[player_index + 1]`), floored at 0.
3. Add `increment_seconds * 1000` to that player's bank (Fischer increment).
4. Set `turn_started_at = NOW()` for the incoming pending player.
5. Set `turn_deadline` based on the next pending player's remaining bank.

If the bank reaches 0 and `increment_seconds` is 0 (or null), the deadline is set to `NOW()`. Any subsequent submit attempt by that player fails with "Turn has expired" because the stored deadline is already in the past.

### Timeout Handling

`private.expire_turn(game_id)` is called by pg_cron for any game where `turn_deadline < NOW()`. It:
1. Acquires a `FOR UPDATE` lock and re-checks the deadline (guards against a concurrent `submit_action`).
2. In budget mode, zeroes the timed-out player's bank (`player_times[player_index + 1] := 0`).
3. Calls `game_apply_action` with `{"type": "timeout"}` — the hook decides the consequence (forfeit, skip, fold, etc.).
4. Applies the same deadline precedence chain for the next turn.

### Budget Mode Requires Sequential Pending

Budget clocks are a sequential concept by nature. The whole point of an accumulated clock is to meter *individual thinking time* — how long each player spends deliberating before they commit. This only has meaning when players act one at a time. It does not have a clean meaning when multiple players are pending simultaneously, for two reasons:

**Timeout cannot be partial.** `expire_turn` fires when the deadline passes (i.e. when the first player's bank runs dry). At that point, some pending players may be timed out while others still have remaining bank. Handling this correctly would require `expire_turn` to partition pending players into "timed out" and "still live" groups, call `game_apply_action` only for timed-out players, eagerly deduct elapsed from the remaining players' banks, and reset the deadline from the new minimum. The hook contract has no clean way to express "one player timed out but others are still pending in the same simultaneous round," and the sequential calling of the hook for logically simultaneous timeouts would produce arbitrary, ordering-dependent outcomes.

**The pairing doesn't occur in real games.** Accumulated clocks exist in deliberative sequential games (chess, correspondence Go) where thinking time is the scarce resource. Simultaneous-commitment games (RPS, secret bidding, poker showdowns) are inherently fast and action-oriented — the natural choice there is a per-action timer or no timer at all. No game in the target list combines the two.

**Rule for implementors:** if your game has any phase where `pending_players` contains more than one index, do not use `budget_seconds`. Use `turn_seconds` (per-action) for those phases, or return `"turn_seconds": N` from the hook for that specific action to give all pending players a shared fixed window. Budget mode is reserved for games where exactly one player is pending at any given time.

### Client-Side Display

Clients receive all timing fields through their `observations` Realtime subscription — no extra queries needed:

- `turn_deadline` → countdown timer (works for all modes)
- `player_times` + `turn_started_at` → live accumulated clock per player

```dart
// Live remaining budget for the active player (budget mode only):
final elapsed = DateTime.now().difference(obs.turnStartedAt!).inMilliseconds;
final remaining = obs.playerTimes![myPlayerIndex] - elapsed;
```

> **Known limitation — device clock skew.** All countdowns compare server
> timestamps (`turn_deadline`, `turn_started_at`) against `DateTime.now()`.
> A device with a skewed clock displays a wrong countdown and may fire
> `trigger_turn_expiry` early (harmless — the server re-validates under
> lock) or late (the pg_cron backstop catches it). Enforcement is never
> affected; only the displayed value is. A future fix would estimate a
> server-time offset from `observations.updated_at` at receipt and apply
> it in the timer builders.

#### Client-Side Expiry Trigger

The game screen maintains a `_deadlineTimer` (`dart:async Timer`) scheduled to fire when `turn_deadline` is reached. On fire it calls `trigger_turn_expiry` — a safe, idempotent nudge that lets the server process the timeout before pg_cron runs (which may fire on a coarse schedule). The server re-validates under `FOR UPDATE` lock, so concurrent calls from multiple active clients are safe.

Any active participant — not just the player whose time ran out — should trigger expiry. If Player A times out but has the app backgrounded, Player B's client drives the expiry immediately.

#### Client-Side Timing Widget System

The timing widget stack follows the **builder pattern** — computation is separated from rendering so game implementors can style clocks however they want.

**Computation layer** (`timer_builders.dart`):

| Widget | Purpose |
|--------|---------|
| `TurnTimerBuilder` | Owns a `Timer.periodic(1s)`, ticks toward a deadline, self-cancels at zero. Exposes `Duration remaining` to a `builder` callback. |
| `PlayerTimerBuilder` | Owns a `Timer.periodic(1s)`, computes one player's remaining budget (live drain for the active player, static for inactive). Exposes `(int remainingMs, bool isActive)` to a `builder` callback. |

**Infra-owned styled shells**:

| Widget | Wraps | Display |
|--------|-------|---------|
| `TurnCountdown` | `TurnTimerBuilder` | `"12m 34s"` / `"45s"`, error-red under 60 s. `StatelessWidget`. |
| `BudgetClock` | `PlayerTimerBuilder` per cell | Row of `"M:SS"` cells, one per player. Each cell rebuilds independently. `StatelessWidget`. |

**Infra-owned header** (`_TimingHeader` in `game_screen.dart`): auto-dispatches on timing mode — `BudgetClock` if `game.budgetSeconds != null`, `TurnCountdown` if `turnDeadline != null`, nothing if untimed. Shown above the game content widget.

**`TimingContext`** (`core/game/timing_context.dart`): passed as a required argument to `GameModule.buildContent`. Carries `playerTimes`, `turnStartedAt`, and `turnDeadline` from the latest observation so game content widgets can render custom timing UI without depending on Riverpod providers directly.

Game implementors who want custom clock placement (e.g. Chess showing each player's clock next to their captured pieces) use `TurnTimerBuilder` / `PlayerTimerBuilder` directly with `timingContext` values. See the Game Implementation Guide §Timing Widgets for examples.

#### Known Limitation — Budget Mode + Hook-Override `turn_seconds`

When a hook returns `turn_seconds` for a specific action inside a budget mode game (e.g. an Exploding Kittens–style Nope interrupt window where multiple players are simultaneously pending), the `_TimingHeader` still shows `BudgetClock` because `game.budgetSeconds != null`. The `PlayerTimerBuilder` marks every player in `pendingPlayers` as "active" and visually drains their banks, but the server is using the hook's fixed window — not touching any player's bank. The display is misleading for that phase.

The root cause is that the client cannot distinguish between a bank-consuming deadline and a hook-override deadline from the observation fields alone. A correct fix requires the server to include a `deadline_type` field (e.g. `"budget"` vs `"hook_override"`) in the `observations` row so the client can switch to a shared `TurnCountdown` for hook-override phases. Until that schema change is made, games that combine budget mode with hook-override `turn_seconds` on multi-player-pending phases should be aware of this visual inaccuracy.

---

## 4. Game Hooks (Infra ↔ Game Contract)

The entire game-specific surface is **four** PostgreSQL functions in the `private` schema. Replacing them produces a completely different game with no other changes.

### `game_rating_pool(p_access, p_turn_seconds, p_budget_seconds, p_increment_seconds, p_min_players, p_max_players, p_config)` → TEXT

Called by `create_game` to decide whether and how a game affects ratings. Returns `NULL` (unrated) or a pool name string (e.g. `'rapid'`, `'daily'`).

This is purely server-side logic — clients pass a `rated_preference BOOLEAN` but can never forge a pool name. If the hook returns `NULL`, the game is forced unrated even if the client requested rated. See the Game Implementation Guide §Hook 0 for the full contract and an example TicTacToe override.

### `game_initial_state(p_seed, p_config, p_player_count)` → envelope

Returns the starting envelope:
```json
{
  "state":           { /* game-specific starting payload */ },
  "pending_players": [0],
  "rng_seed":        12345678901234567
}
```
- `state`: pure game payload (board, deck, fog map…). Never put whose-turn or winner info here.
- `pending_players`: 0-based indices that may act first.
- `rng_seed`: **required, non-zero.** Return the advanced seed after consuming any setup randomness (`private.prng_next`). Infra raises if null or zero.
- `turn_seconds` (optional): fixed deadline for the very first action only (overrides budget/default). Omit to use the game's configured timing mode.

### `game_apply_action(p_state, p_pending, p_data, p_player_index, p_rng_seed, p_config)` → envelope

Called by `submit_action` and `expire_turn`. Returns the updated envelope.

Ongoing move — `outcome` key absent:
```json
{ "state": { /* updated payload */ }, "pending_players": [1], "rng_seed": 98765432109876543 }
```

Game over — `outcome` key present:
```json
{ "state": { /* updated payload */ }, "pending_players": [], "outcome": [ … ], "rng_seed": 98765432109876543 }
```

- `state`: new game payload.
- `pending_players`: who acts next. Empty array = game over.
- `outcome`: **Omit this key when the game is ongoing.** Infra treats an absent key as SQL `NULL` — no JSONB null needed. Include it only when the game ends, as an array of per-player results:
  ```json
  [
    { "player_index": 0, "result": "win",  "placement": 1, "team_index": 0 },
    { "player_index": 1, "result": "loss", "placement": 2, "team_index": 1 }
  ]
  ```
  Required keys: `player_index` (int), `result` (`"win"` | `"loss"` | `"draw"` | `"eliminated"`), `placement` (int, 1 = best, ties share the same value), `team_index` (int, use `player_index` for individual games). Optional: `"score"` (numeric). Infra writes these to `game_outcomes` and sets `games.status = 'finished'`. See §8 for team game examples.
- `rng_seed`: **required, non-zero.** Advance via `private.prng_next` for every random value consumed.
- `turn_seconds` (optional): fixed deadline for **this action only** — does not touch any player's bank. Use this for phase-specific timing (Nope window, betting round). Omit to let infra apply the game's configured timing mode.

The infra layer has already gated on `pending_players` before calling this hook, so you do **not** need to re-check whose turn it is for the sequential case.

### `game_compute_observation(p_state, p_pending, p_player_index, p_participant_count, p_config, p_is_replay)` → envelope

Called once per participant by `update_all_observations` and `start_game`. Also called by `get_replay` for every historical version. Returns:
```json
{
  "data":            { /* this player's view of the state */ },
  "pending_players": [0, 1]
}
```
- `data`: what this specific player is allowed to see.
- `pending_players`: may be narrowed from the true pending set for hidden-info games (e.g. only expose Nope eligibility to players who hold the card).
- `p_is_replay` (`BOOLEAN DEFAULT FALSE`): `TRUE` when called from `get_replay` on a finished game. Hidden-info games can use this flag to reveal opponent state post-game (e.g. show all hole cards in Poker replay). Live calls always pass `FALSE`.

**Perfect-info games do not override this** — the default passthrough is already implemented by infra.

---

## 5. RPC Functions (Infra — Do Not Modify)

| RPC | Caller | Purpose |
|-----|--------|---------|
| `create_game(access, turn_seconds, budget_seconds, increment_seconds, min_players, max_players, config, rated_preference)` | Client | Creates the `games` row with a unique `short_code` (retry loop on collision) and adds the creator as participant 0. Validates timing exclusivity and player count range. Calls `private.game_rating_pool()` to derive `rated` and `rating_pool` server-side; `rated_preference` is overridden to false if the hook returns `NULL`. |
| `join_game(game_id, client_schema_version)` | Client | Adds a participant; rejects if already at `max_players`; transitions to `ready` when count ≥ `min_players`. For `friends` access games, validates that the caller is an accepted friend of the game creator via `relationships`. Refuses to seat the caller when `games.schema_version` exceeds the client's `client_schema_version` (the build's `GameModule.schemaVersion`), under the same `FOR UPDATE` lock — so a client never becomes a participant in a game it cannot render. The parameter is required (not defaulted): omitting it fails rather than silently skipping the gate. See §24. |
| `join_game_by_code(code, client_schema_version)` | Client | Looks up a game by `short_code`, then delegates to `join_game` (forwarding the schema gate, since the by-code/deep-link paths cannot inspect the game client-side before joining). Returns the game ID. Raises if not found. |
| `leave_game(game_id)` | Client (non-creator) | Removes the calling participant from a `waiting` or `ready` game. Transitions game back to `waiting` if count drops below `min_players`. Creator cannot leave — they must cancel instead. |
| `start_game(game_id)` | Client (host) | Calls `game_initial_state`, creates `game_states` and per-player `observations` rows (via `game_compute_observation`), initialises `player_times` if budget mode, sets `turn_started_at`, marks game `active`. |
| `cancel_game(game_id)` | Client (host) | Aborts a `waiting` or `ready` game. Sets `games.status = 'aborted'`. |
| `forfeit_game(game_id)` | Client | Forfeits an `active` game. No version check — forfeiting is an unconditional intent; the `FOR UPDATE` row lock serialises it against concurrent actions. Calls `game_handle_system_action` with `p_action_type = 'forfeit'`. The hook decides the consequence (typically: forfeiting player loses, opponent wins). |
| `submit_action(game_id, data, expected_version)` | Client | Row-locks `games` (serializes all concurrent writers for this game), validates version and deadline, gates on `pending_players`, calls `game_apply_action`, deducts bank if budget mode, applies deadline precedence chain, fans out per-player observations, writes `game_outcomes` on game end. |
| `trigger_turn_expiry(game_id)` | Client | Client-side nudge: calls `expire_turn` immediately when the client detects the deadline has passed. Safe to call from any active participant — server re-validates under `FOR UPDATE` lock. Errors are expected and swallowed when the game has already advanced. |
| `expire_turn(game_id)` | pg_cron | Backstop cron: row-locks `games`, re-validates deadline, zeroes timed-out player's bank (budget mode), calls `game_handle_system_action` with `p_action_type = 'timeout'`, fans out observations. |
| `get_replay(game_id)` | Client | Returns the caller's observation slice at every historical version as a JSONB array. Only available for finished games; caller must be a participant. Projects each `game_states` row through `game_compute_observation` — never exposes raw state. Post-game reveal rules (hidden-info games) are defined entirely in the hook. |

### Version Conflicts

`submit_action` is guarded by an optimistic lock: the client passes the
`version` it last observed, and `private.validate_version` raises
`Stale state: expected version X, current Y` if another writer committed first.
The client does not retry automatically — it surfaces the conflict as a
humanized "board updated — try again" message (`error_messages.dart`), letting
the player re-act against the state the Realtime stream has by then delivered.

> Simultaneous games (multiple players pending in one round) will hit this
> routinely with spurious conflicts; handling that is tracked in
> `future_plans.md`.

### Account Management RPCs

| RPC | Caller | Purpose |
|-----|--------|---------|
| `delete_account()` | Client | Permanently deletes the caller's account. See §22 for the full deletion flow. |
| `update_username(new_username)` | Client | Validates format and uniqueness (case-insensitive), updates `users.username`. |

### Social RPCs

| RPC | Caller | Purpose |
|-----|--------|---------|
| `send_friend_request(target_user_id)` | Client | Creates a `pending` relationship. If the target already has a pending request to the caller, auto-accepts it (mutual add). Self-requests raise. `ON CONFLICT DO NOTHING` prevents duplicates. |
| `accept_friend_request(target_user_id)` | Client | Transitions a `pending` relationship to `accepted`. Only the recipient (non-initiator) can accept. |
| `remove_friend(target_user_id)` | Client | Deletes the relationship row entirely — works for both accepted friendships and pending requests. |
| `search_users(query)` | Client | Returns up to 20 human-only results (id, username, display_name, avatar_url) matching `username` or `display_name` via `ILIKE` (backed by trigram indexes). Queries `users`/`user_profiles` directly — bots never appear in search results. |

### Game Discovery RPCs

| RPC | Caller | Purpose |
|-----|--------|---------|
| `get_lobby_games(cursor, limit)` | Client | Returns public waiting/ready games with embedded participants. Cursor-paginated by `created_at`. Requires `authenticated` — anonymous browsing is not permitted. |
| `get_friends_games(cursor, limit)` | Client | Returns `friends`-access waiting/ready games created by the caller's accepted friends — plus the caller's own rooms (you are not "friends with yourself", so the relationship check alone would hide them) — with embedded participants and `is_participant` flag. Cursor-paginated by `created_at`. Only games that are not full (participant count < `max_players`) are returned. |

### Client Query Patterns (Not RPCs)

The Dart client uses PostgREST embedded selects for efficient single-round-trip queries:

- **Active games dashboard**: `games` with embedded `participants!inner(user_id, player_index)` and `observations(pending_players, turn_deadline)` — derives `myPlayerIndex`, `pendingPlayers`, and `turnDeadline` in one query.
- **Public lobby**: `get_lobby_games(cursor)` RPC returns public waiting/ready games with embedded participants. Cursor-paginated by `created_at` with page size 50.
- **Friends lobby**: `get_friends_games(cursor)` RPC returns friends-access games. The lobby screen uses a swipeable `TabBar` + `TabBarView` to switch between public and friends modes; each tab widget uses `AutomaticKeepAliveClientMixin` so the paged list is retained on tab switch without a re-fetch.
- **History**: `games` filtered to `finished` / `aborted` status, with embedded `participants!inner`, `game_outcomes`, and `rating_history` — derives `myResult` and the current user's `RatingChange?` per game in a single query. RLS on `rating_history` automatically filters embedded rows to the current user, so no explicit user filter is needed. Cursor-paginated by `finished_at` descending with page size 30.

---

## 6. Hidden Information

`game_states` is service-role only. Clients never see the ground truth directly. Each player receives only their personal `observations` row, which is computed by `game_compute_observation` after every state change. This makes hidden-info games (Poker, Literature, Exploding Kittens, Mafia) structurally secure — the server computes each player's slice and Realtime pushes only that slice to the right subscriber.

RLS on `observations` (`user_id = auth.uid()`) means a client subscribing to `game_id = X` receives at most one row — their own.

---

## 7. Player Identity System

Player identity is resolved and cached independently from game-specific data, ensuring usernames and avatars are available across all screens without redundant network calls.

### Scope: Game Identity vs Social Identity

| | Game identity (`get_players` RPC) | Social identity (base tables) |
|---|---|---|
| **Covers** | Humans and bots | Humans only |
| **Used by** | `playerInfoCacheProvider`, `gamePlayers`, lobby/game display | `search_users`, friend RPCs, relationship UI |
| **Source** | UNION of `users`+`user_profiles` and `bots` | `users` and `user_profiles` directly |
| **Why separate** | In a game, the seat holder may be a bot — it needs a name and avatar. In social contexts, bots are not people and cannot be friended, searched for, or invited. |

### Data Flow

```
 get_players(uuid[]) RPC (DB) ← unified UNION of users+bots
        ↓
 playerInfoCacheProvider(id)  ← keepAlive + SQLite persist, works for any player UUID
        ↓
 gamePlayersProvider(gameId)  ← fetches participants, resolves identities
        ↓
 PlayersContext                ← passed to buildContent()
  └── Map<int, GamePlayer>    ← playerIndex → {type, info}
```

### Models

**`PlayerInfo`** (`shared/data/models/player_info.dart`) — canonical public player identity for both humans and bots:
- `id` (String) — user or bot UUID
- `username` (String)
- `displayName` (String?)
- `avatarUrl` (String?)

The bot/human distinction is carried by `GamePlayer.type` (`ParticipantType.human` or `ParticipantType.bot`), not by the identity model. `get_players` returns the same columns for both branches of its UNION, so `PlayerInfo.fromJson` parses both identically.

**`GamePlayer`** (`core/game/game_player.dart`) — unified game-level player concept:
- `playerIndex` (int) — 0-based seat
- `type` (ParticipantType)
- `info` (PlayerInfo) — resolved identity

(Per-game roles are not modelled here — they live in the game's observation/
state JSON, interpreted by the game module.)

**`PlayersContext`** (`core/game/players_context.dart`) — passed to `buildContent`:
- `players` (Map<int, GamePlayer>) — all players keyed by index
- `myPlayerIndex` (int) — current user's seat (-1 if spectating)
- `operator [](int)` → `GamePlayer` — non-nullable access
- `me` → `GamePlayer` — convenience accessor

### Provider Architecture

`playerInfoCacheProvider(id)` is `keepAlive: true` + `@JsonPersist()`. Works for both human and bot IDs — `get_players` covers both via a UNION. On cold start, resolves from SQLite cache (~5 ms) while the network fetch runs in background. Held in memory for the entire session after first access. See §23 for the full persistence design.

`gamePlayersProvider(gameId)` is auto-dispose — a session touches many games (home cards, history navigation), and keeping every game's context alive forever would grow without bound. Re-fetching is cheap because identities resolve from the persisted `playerInfoCacheProvider`; only the participants query runs. It fetches participants, resolves each identity via `playerInfoCacheProvider(id: p.userId ?? p.botId!)` in parallel (XOR constraint guarantees one is non-null), assembles `GamePlayer` objects, and returns a complete `PlayersContext`. The game screen shows a loading indicator until this resolves, then calls `buildContent()` with guaranteed non-nullable data.

### Cross-Screen Availability

| Screen | How it uses player identity |
|--------|----------------------------|
| **Lobby** | Watches individual `playerInfoCacheProvider(id)` per participant (inline from RPC). Pre-warms the cache for game screen navigation. |
| **Home** | Watches `gamePlayersProvider(gameId)` per game card. Extracts `PlayerInfo` for `OverlappingAvatars`. |
| **Game** | Watches `gamePlayersProvider(gameId)`. Passes `PlayersContext` to `buildContent()`. Pre-game waiting room uses same data. |

### Profile Picture Updates

When a user updates their avatar, display name, or username via `CurrentUserProfile`, `ref.invalidate(playerInfoCacheProvider(id: userId))` is called automatically — so game screens, lobby cards, and friend lists reflect the change immediately without waiting for a cold start.

### Shared Widgets

- `PlayerAvatar` — displays avatar with network image caching, person-icon fallback, and optional border. `onTap` is optional; when `null` the widget is fully non-interactive (no `GestureDetector`). In `ListTile` contexts leave `onTap` unset — `ListTile.onTap`'s `InkWell` covers the whole row including the leading avatar. Pass `onTap` only when the avatar is used standalone (e.g. a standalone tappable icon outside a list tile).
- `OverlappingAvatars` — renders a row of overlapping `PlayerAvatar` circles for game cards.
- `PlayerProfileSheet` — modal bottom sheet showing a player's public profile: identity header, ratings across all pools, and friendship actions (humans only). Open via `PlayerProfileSheet.show(context, playerId: id, type: type)`. Bot profiles show identity and ratings with no social section. When `playerInfoCacheProvider` fails (e.g. deleted account), the sheet shows `_DeletedPlayerHeader` — a tombstone icon with "Player not found" and "This account no longer exists." — instead of an error string.
- `EmptyStateView` — illustrated empty state for list screens. Renders a 96×96 icon in a `primaryContainer` circle, a `titleLarge` heading, a `bodyLarge` subdued message, and an optional call-to-action button. Use `tonalCta: true` for soft nudges (`FilledButton.tonal`), false (default) for primary creation actions (`FilledButton`). Used by all five list screens: Home, Lobby, History, Friends, and Friend Requests.

---

## 8. Rating System

The rating system uses **OpenSkill** (a Bayesian algorithm similar to TrueSkill) to rank players. Ratings are stored in `player_ratings` (current state) and `rating_history` (immutable per-game log), keyed by player and pool (e.g. `'rapid'`, `'daily'`).

### Rating Parameters

Each player's skill is a Gaussian: `mu` (mean, default 25.0) and `sigma` (uncertainty, default `25.0 / 3.0 ≈ 8.33`). The conservative **display rating** is:

```
display_rating = max(0, round((mu − 3 × sigma) × 40))
```

A new player (mu=25, sigma=25/3) displays 0 — a deliberately conservative estimate. As sigma shrinks with each game, the display rating reflects actual skill more closely.

### Required Outcome Fields

Both `placement` and `team_index` are `NOT NULL` on `game_outcomes`. Every outcome entry in the array returned by the game hooks must supply them:

| Field | Description |
|-------|-------------|
| `placement` | Ordinal finish rank (1 = best). Ties share the same value. Passed directly to OpenSkill as the rank input. |
| `team_index` | Groups players into rating teams. Players sharing a value move together. Use `player_index` for individual games (each player is their own team of one); teammates share a value for team games. |

**Individual 1v1 win/loss:**
```json
[
  { "player_index": 0, "result": "win",  "placement": 1, "team_index": 0 },
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
  { "player_index": 0, "result": "win",  "placement": 1, "team_index": 0 },
  { "player_index": 2, "result": "win",  "placement": 1, "team_index": 0 },
  { "player_index": 1, "result": "loss", "placement": 2, "team_index": 1 },
  { "player_index": 3, "result": "loss", "placement": 2, "team_index": 1 }
]
```

**N-player with bust-out placements (Poker):**
```json
[
  { "player_index": 0, "result": "win",        "placement": 1, "team_index": 0 },
  { "player_index": 2, "result": "eliminated", "placement": 2, "team_index": 2 },
  { "player_index": 1, "result": "eliminated", "placement": 3, "team_index": 1 },
  { "player_index": 3, "result": "loss",       "placement": 4, "team_index": 3 }
]
```

Individual games are the degenerate case of the team model — each player is their own team of one. OpenSkill's `rate()` handles both uniformly.

### Production Configuration

Two values must be set once per environment before the rating pipeline is active. Local dev is handled automatically by `seed.sql` via `supabase db reset`.

**1. `serverless_base_url` — insert into `private.app_config`**

Run in the Supabase SQL editor (replace the URL with your project's edge function base URL):

```sql
INSERT INTO private.app_config (key, value, description)
VALUES (
  'serverless_base_url',
  'https://<project-ref>.supabase.co/functions/v1',
  'Base URL for serverless functions'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

**2. `serverless_secret` — create in Vault**

First, generate a secure random secret:

```bash
openssl rand -base64 32
```

Use the output as the secret value below and in the edge function's `SERVERLESS_SECRET` environment variable. The two must match.

Option A — Supabase Dashboard: **Database → Vault → Add secret**. Set name to `serverless_secret` and value to the generated secret.

Option B — Supabase SQL editor:

```sql
SELECT vault.create_secret(
  'your-secret-value',
  'serverless_secret',
  'Shared secret verified by all serverless functions'
);
```

To update an existing Vault secret:

```sql
SELECT vault.update_secret(
  (SELECT id FROM vault.secrets WHERE name = 'serverless_secret'),
  'your-new-secret-value',
  'serverless_secret',
  'Shared secret verified by all serverless functions'
);
```

### Update Pipeline

When a rated game transitions to `finished`, a pg_net trigger fires the edge function asynchronously:

```
games.status → 'finished'  (rated = true)
        ↓  AFTER UPDATE trigger
private.notify_rating_update()
        ↓  pg_net async HTTP POST
update-ratings edge function  (Deno — pure computation, no DB reads)
        ↓  OpenSkill rate()
public.apply_rating_updates RPC  (service_role only)
        ↓  single atomic transaction
player_ratings (upsert) + rating_history (insert)
```

1. **`private.notify_rating_update()`** fires on the first `finished` transition of a rated game. Bundles each player's current `mu`/`sigma`/`display_rating` from `player_ratings` (LEFT JOIN — defaults to new-player values if no prior row) alongside `placement` and `team_index` from `game_outcomes`. Skips with `RAISE WARNING` if `serverless_base_url` is absent from `private.app_config` or `serverless_secret` is absent from Vault.

2. **`update-ratings` edge function** is a stateless computation service. Receives the self-contained payload, groups players by `team_index`, calls OpenSkill's `rate(teams, {rank: placements})`, and returns `RatingUpdate[]` with before/after snapshots to the RPC. Never reads the database.

3. **`public.apply_rating_updates`** performs the atomic write — upserts `player_ratings` and inserts into `rating_history`. Restricted to `service_role` via `REVOKE EXECUTE FROM anon, authenticated`; clients cannot call it directly.

### Idempotency

The trigger's `OLD.status = 'finished'` guard prevents double-fire in normal operation. `rating_history` unique partial indexes — `(game_id, user_id)` and `(game_id, bot_id)` — ensure duplicate edge function calls for the same game are harmless at the DB level: the duplicate call's insert is rejected (the call errors), so ratings are never double-applied.

> **Known limitation — concurrent rated finishes.** `notify_rating_update`
> snapshots each player's `mu`/`sigma` at trigger time. If two rated games
> involving the same player finish near-simultaneously, both payloads carry
> the same "before" rating and the later `apply_rating_updates` overwrites
> the earlier — one game's rating effect is lost. Closing this would require
> `apply_rating_updates` to lock `player_ratings` rows and recompute from
> the stored values instead of trusting the payload, at the cost of the
> edge function's "pure computation, no DB reads" design. Accepted for now:
> the window is milliseconds wide and one player cannot realistically finish
> two games at once.

### Rating Pools

`private.game_rating_pool()` derives the pool name server-side at game creation. Clients pass a `rated_preference` boolean but cannot forge pool names. A `NULL` return forces the game unrated regardless of client preference.

---

## 9. Event Sourcing & Replayability

`game_states` is an **append-only history table**. One row is inserted per state transition (including version 0 for the initial state), so the full game history is always available at zero extra cost — no action log re-execution needed.

### Replay via `get_replay`

The `get_replay(game_id)` RPC returns the caller's observation slice at every version:

```
get_replay(game_id)
  → for each row in game_states LEFT JOIN actions ON version_after = version:
       game_compute_observation(state, pending_players, player_index, …, is_replay=true)
  → [{version, data, pending_players, created_at,
      action_type, action_data, action_player_index}, …]
```

Each frame:
- `version` — 0-based state index (version 0 is the initial state)
- `data` — game-specific observation for the caller (output of `game_compute_observation`)
- `pending_players` — who was pending at this version (post-hook narrowing applied)
- `created_at` — when this state was committed
- `action_type` — `"user"` / `"system"` / `"bot"`; `null` for version 0 (no action produced it)
- `action_data` — raw action payload (e.g. `{"position": 4}` or `{"type":"timeout","player_index":1}`); `null` for version 0
- `action_player_index` — 0-based seat index of the player who **chose** to act, read directly from `actions.player_index` (denormalized at write time — survives user deletion). `null` for version 0 and for anonymous system events (timeout, auto_forfeit) where no single player initiated the action. Set for user moves, bot moves, and forfeits (player voluntarily initiated). Flutter reads `action_data->>'player_index'` when it needs to know which player a timeout *affected*.

- Only finished games are replayable. `get_replay` raises if `status != 'finished'`.
- The caller must be a participant. Non-participants (spectators) cannot replay.
- Raw state is **never** exposed — every version is projected through `game_compute_observation`. Post-game hidden-info reveal (e.g. a poker hand-history that still hides folded hands) is controlled entirely by the hook. If the hook reveals full state when `pending_players` is empty, the replay shows it; if it doesn't, the replay doesn't.
- The `actions` table remains an audit log. `version_after` on each action row links it to the `game_states` version it produced, enabling `WHERE version_after = N` joins for per-action inspection.

### What the action log gives you

- **Timeouts as actions**: `expire_turn` inserts a system action (`type = 'system'`, `data = {"type":"timeout","player_index":N}`), so timeouts appear in the log alongside the resulting state row.
- **Forfeits as actions**: `forfeit_game` inserts a system action (`type = 'system'`, `data = {"type":"forfeit","player_index":N}`).
- **Correlation**: `actions.version_after` = `game_states.version` for the state snapshot the action produced. A JOIN on this column reconstructs "which action caused this state" for any audit or cheat-detection tool.

---

## 10. Security Model

- **Optimistic locking**: clients pass `expected_version`; `submit_action` rejects stale versions. `forfeit_game` deliberately has no version check — forfeiting is an unconditional intent, and the row lock alone keeps the action/state history ordered.
- **Row lock**: `FOR UPDATE` on `games` serializes all concurrent writers (`submit_action`, `forfeit_game`, `expire_turn`, `trigger_turn_expiry`) for the same game. Because `game_states` is append-only (no single mutable row to lock), the lock migrated to `games`. `FOR UPDATE` acquires a row lock without writing, so no Realtime events fire on `games` during normal gameplay — only `finish_game()` writes to `games`, and that write was already there.
- **TOCTOU-free status check**: `submit_action` and `forfeit_game` merge the game-status check into the same `FOR UPDATE` read. There is no separate pre-lock status read that could race with a concurrent `finish_game`.
- **Deadline guard**: `submit_action` rejects any action where `turn_deadline < NOW()` (checked after the lock).
- **`expire_all_turns` isolation**: the pg_cron sweep uses `DISTINCT ON (game_id) ORDER BY version DESC` to select only the latest deadline per game, ignoring stale deadlines in historical rows.
- **Deterrence audit**: if a client detects an illegal opponent action, it calls `flag_game`. An Edge Function replays the full action history; confirmed cheating triggers a ban and annuls the game.
- **Ratings audit**: an Edge Function validates the full action history before writing rating updates.

### RPC Security Pattern

Every client-callable RPC uses a single-layer `SECURITY DEFINER` pattern:

```sql
CREATE FUNCTION public.<fn>(…)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$ … $$;

REVOKE EXECUTE ON FUNCTION public.<fn>(…) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.<fn>(…) TO authenticated;
```

- The function lives in the `public` schema (accessible via PostgREST) with `SECURITY DEFINER` — it runs as the function owner (postgres), allowing writes to service-role-only tables (`game_states`, `actions`, `game_outcomes`, `auth.users`).
- `SET search_path = ''` on every function prevents search-path injection attacks.
- Permissions are explicit: `REVOKE EXECUTE FROM PUBLIC, anon` + `GRANT TO authenticated` — no implicit public access.
- Internal utility functions (`private.require_auth`, `private.get_participant`, `private.notify_rating_update`, etc.) remain in the `private` schema. They are called by the public `SECURITY DEFINER` functions and are never exposed via PostgREST.

> **History note**: An earlier version used a two-layer pattern — a thin `public.*` `SECURITY INVOKER` wrapper calling a `private.*` `SECURITY DEFINER` implementation. This was removed (commit `9c4c901`) because the wrapper added noise without a security benefit: both layers ran within the same Postgres session under the same elevated role.

---

## 11. Implementation Phases

### Phase 1 ✓ — Core Shell
Auth, dashboard, settings, `users`/`user_profiles` tables, Material 3 theming.

### Phase 2 ✓ — Networking & Infra
Full schema (`games`, `game_states`, `participants`, `observations`, `actions`, `game_outcomes`), all RPC functions, PRNG, timing system, and a reference game implementation.

Client features:
- Home screen with active games, "your turn" sorting, live `TurnCountdown` on cards, pull-to-refresh with staleness label.
- Lobby with paginated public games, per-game player count (embedded participant query), wait duration.
- Game screen with Realtime observation stream, pre-game waiting room (join/leave/cancel/start), in-game board, forfeit with confirmation dialog.
- History screen with paginated finished games and per-game outcome result.
- Client-side expiry trigger (`trigger_turn_expiry`) fired when the client detects `turn_deadline` has passed.
- Timing widget system: `TurnTimerBuilder`, `PlayerTimerBuilder` (headless builder widgets), `TurnCountdown`, `BudgetClock` (infra-owned styled shells), `TimingContext` passed to all `buildContent` calls.

### Phase 2.5 ✓ — Social & Friends
Friends system (`relationships` table, `friends_view`), friend RPCs (`send_friend_request`, `accept_friend_request`, `remove_friend`), user search with trigram indexes.

Game discovery:
- Short codes on games for invite-by-code joining (`join_game_by_code`).
- `friends` access enforcement in `join_game` (validates accepted friendship with creator).
- Friends lobby (`get_friends_games` RPC) with Public/Friends segmented toggle in lobby screen.
- Join-by-code flow: `/join/:code` route, `JoinGameScreen`, join code dialog on home screen.

Client features:
- Social screen with three tabs: Friends (accepted), Requests (incoming pending), Add Friend (search + send). Each tab uses `AutomaticKeepAliveClientMixin` so switching tabs does not re-fetch the list. Each list item is its own `ConsumerWidget` (`_FriendTile`, `_RequestTile`) that independently watches `playerInfoCacheProvider(id)` — only the affected tile rebuilds when a player's identity changes, not the whole list.
- Social navigation branch in shell scaffold.
- Pre-game waiting room displays short code for private/friends games.

### Phase 3 — Advanced Game Features
Additional games (Chess, Go, Literature, Poker, Exploding Kittens). Edge Function validation for revelation actions. Push notifications for async games.

### Phase 4 ✓ — Rating & Bots

OpenSkill (Bayesian) rating system:
- `bots` table: bot player registry with username/display_name/avatar_url identity.
- `player_ratings` table: per-player per-pool mu/sigma/display_rating, upserted after each rated game.
- `rating_history` table: immutable per-game audit log with before/after snapshots.
- `private.game_rating_pool()`: 4th game hook — server derives the pool name from game config; clients cannot forge pool names.
- `private.notify_rating_update()` pg_net trigger: fires when a rated game finishes. Bundles `placement`, `team_index`, and each player's current `mu`/`sigma`/`display_rating` into the webhook payload so the edge function is a pure computation service with no DB dependency.
- `supabase/functions/update-ratings`: Deno 2 edge function using `openskill` (MIT). Groups players by `team_index`, calls `rate(teams, {rank: placements})`, returns computed deltas to `apply_rating_updates`. No DB reads — all inputs arrive in the payload. Idempotent via unique partial indexes on `rating_history`.
- `public.apply_rating_updates`: SECURITY DEFINER RPC restricted to `service_role`. Upserts `player_ratings` and inserts `rating_history` atomically.
- Config: `serverless_base_url` stored in `private.app_config`; `serverless_secret` stored in Supabase Vault. Local dev values seeded via `seed.sql`. Edge function env var: `SERVERLESS_SECRET`.

Client:
- `PlayerInfo` is the unified identity model for both humans and bots — no separate BotInfo type. `get_players(uuid[])` RPC covers both via a UNION. `playerInfoCacheProvider(id)` works for any player UUID.
- `PlayerInfo` does not carry a rating field — detailed per-pool ratings are fetched separately via `myRatingsProvider` (own profile) or `playerRatingsProvider(id)` (other players' profiles / `PlayerProfileSheet`).
- `player_ratings` queryable directly via table RLS (no RPCs needed).
- `rating_history` embedded in `GameRepository.getHistoryGameEntries` alongside `game_outcomes` — not exposed as a standalone client query. Rating deltas (`▲ +N` / `▼ -N`) are shown inline on each history card.

---

## 12. File Structure

This is the **`eigen_engine` package** (its repo root). Paths in this document
written as `lib/core/...`, `lib/features/...`, `lib/shared/...` are relative to
it. An **app** that uses the engine adds it as a dependency and supplies a
`GameModule` plus its own `main.dart`, `env/`, `firebase_options.dart`, platform
folders and Supabase config — see `game_implementation_guide.md` for how a
consuming app is structured.

The engine also ships `bin/sync_supabase.dart` (the backend-vendoring CLI) and the
canonical backend under `supabase/` — `migrations/` (schema + RPCs), `functions/`
(edge functions), and `seed.sql` — alongside `lib/`.

```
lib/
├── eigen_engine.dart                 # Public barrel (runEngineApp, AppConfig, GameModule, …)
├── app_runner.dart                      # runEngineApp(...) entry point + root MyApp
├── core/
│   ├── config/
│   │   └── app_config.dart              # AppConfig (Branding + EngineConfig)
│   ├── game/
│   │   ├── base_engine.dart              # BaseEngine abstraction (local legality only)
│   │   ├── game_creation_spec.dart       # GameCreationSpec, TimingModeConfig variants
│   │   ├── game_frame.dart               # GameFrame — per-event observation snapshot
│   │   ├── game_module.dart              # GameModule contract + GameContentContext
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
│   │   └── player_repository.dart        # Fetches via get_players() RPC (unified humans + bots)
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
│   │   │   │   ├── game_screen.dart      # Game screen — pre-game (with short code display),
│   │   │   │   │                         #   active, finished, aborted
│   │   │   │   ├── history_screen.dart   # Paginated finished/aborted game history with inline rating deltas
│   │   │   │   ├── home_screen.dart      # Active games dashboard + join-by-code dialog
│   │   │   │   ├── join_game_screen.dart # Handles async join-by-code, redirects to game
│   │   │   │   └── lobby_screen.dart     # Public/Friends tabbed game browser (TabBar + AutomaticKeepAliveClientMixin)
│   │   │   └── widgets/
│   │   │       ├── budget_clock.dart     # Infra-owned N-player budget clock (stateless shell)
│   │   │       ├── timer_builders.dart   # TurnTimerBuilder, PlayerTimerBuilder (headless)
│   │   │       └── turn_countdown.dart   # Infra-owned per-action countdown (stateless shell)
│   │   └── providers/
│   │       ├── game_providers.dart       # gamePlayersProvider, activeGamesProvider, etc.
│   │       └── game_frame_provider.dart  # gameFrameProvider, gameEngineProvider, currentGameModuleProvider
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
│       │   └── social_repository.dart    # Friend RPCs + search_users
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
│       ├── data/models/game_models.dart # ObservationData, ActionData, GameConfigData
│       ├── logic/my_game_engine.dart    # BaseEngine implementation
│       ├── presentation/{my_game_board,my_game_content}.dart
│       └── game_module.dart             # MyGameModule
├── android/ ios/ web/ macos/ linux/ windows/
├── assets/                              # google_fonts, icons
└── supabase/                            # config.toml, functions, seed.sql, migrations/ (committed)
```

The engine's infra migrations are **vendored** into the app's committed
`supabase/migrations/` (alongside the app's game hook migration) by the
engine-owned CLI, run from the app: `dart run eigen_engine:sync_supabase`.

---

## 13. App Startup & Splash Screen

The native splash screen is kept visible until the auth state is known, eliminating the GoRouter authentication redirect flash — the redirect from `/home` → `/login` (or vice versa) happens behind the splash.

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

`authStateChangesProvider.future` resolves on the first Supabase stream emission regardless of whether the user has a session — the splash never waits on a network round-trip. No timeout is applied to this await: Supabase Flutter reads the stored session from secure storage and emits `initialSession` locally, so resolution is always fast. The sole exception is an **expired session with no network** — the token-refresh attempt must time out before `signedOut` is emitted. Supabase's own HTTP timeout handles this; enforcing a shorter app-level timeout risks a flash to the login screen on a merely slow (not offline) connection.

`currentUserProfileProvider.future` (awaited only when authenticated) is capped at **2 seconds**. SQLite resolves in ~5 ms so the cap only fires on a first-ever launch with no local cache and no network. In that case the `catch` block fires, `FlutterNativeSplash.remove()` runs in `finally`, and the home screen opens with the profile in a loading/shimmer state — no stuck splash.

### Dart Implementation

**`app_runner.dart`** (engine) — `runEngineApp` captures the binding before any async work and passes it to `preserve()`, then initialises Firebase/Supabase and runs the app. The app's `main.dart` just calls it:

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

**`lib/core/startup/app_startup.dart`** — `ConsumerStatefulWidget` that wraps `MyApp`. Its `initState` awaits `authStateChangesProvider.future` and calls `FlutterNativeSplash.remove()` in a `finally` block so the app is never stuck behind the splash on error.

`flutter_native_splash` is a **runtime dependency** (not dev), required since v2.0.0.

### `pubspec.yaml` Configuration

The `flutter_native_splash:` block is a top-level key — **not** nested under `flutter:`:

```yaml
flutter_native_splash:
  color: "#FFFBFF"                        # Material 3 light surface (deepPurple seed)
  color_dark: "#141218"                   # Material 3 dark surface (deepPurple seed)
  image: assets/splash/logo.png           # centered logo, 1152×1152 px
  image_dark: assets/splash/logo_dark.png # white/light version for dark background

  android_12:                             # covers Android 12, 13, 14, 15, 16+ (API 31+)
    color: "#FFFBFF"
    color_dark: "#141218"
    image: assets/splash/logo.png
    image_dark: assets/splash/logo_dark.png
    icon_background_color: "#FFFBFF"
    icon_background_color_dark: "#141218"

  web: false                              # set true to generate a web splash
```

Colors must stay in sync with the branding seed (`Branding.seedColor`, set in
`main.dart`). The native splash config can't read Dart, so if the seed color
changes, update both `color`/`color_dark` here and regenerate.

### Asset Requirements

Declare the folder in `pubspec.yaml` under `flutter: assets:` before adding files:

```yaml
flutter:
  assets:
    - assets/splash/
```

**Required:**

| File | Size | Notes |
|------|------|-------|
| `assets/splash/logo.png` | **1152 × 1152 px** | Light-mode logo. Keep artwork within the inner **640 px** — the outer ring is cropped by Android 12's circular icon mask. |
| `assets/splash/logo_dark.png` | **1152 × 1152 px** | Dark-mode logo (white/light version for dark background). |

The generator produces all Android density variants (mdpi → xxxhdpi) from these single sources. Do not create per-density files manually.

**Optional — bottom branding (studio name, tagline):**

| File | Size | Notes |
|------|------|-------|
| `assets/splash/branding.png` | ≥ 600 px wide | Add `branding:` and `branding_bottom_padding:` to the config block. |
| `assets/splash/branding_dark.png` | ≥ 600 px wide | Dark variant. |

### Regenerating Platform Files

Run after any change to the `flutter_native_splash:` config block or splash image assets:

```bash
dart run flutter_native_splash:create
```

**Generated files — do not edit manually:**

| File(s) | Applies to |
|---------|-----------|
| `android/.../drawable*/launch_background.xml` + `background.png` | Pre-Android 12 (all densities) |
| `android/.../values/styles.xml` + `values-night/styles.xml` | Android ≤ 11 — `windowBackground` drawable |
| `android/.../values-v31/styles.xml` + `values-night-v31/styles.xml` | Android 12+ — `windowSplashScreenBackground` |
| `ios/Runner/Info.plist` | iOS status bar configuration |

### Android API Boundary

`-v31` is a **minimum-version qualifier**, not an exact match. The `android_12:` config block covers every Android release from API 31 onwards:

| Resource folder | Android version | Mechanism |
|---|---|---|
| `values/` | ≤ 11 (API ≤ 30) | `android:windowBackground` drawable |
| `values-v31/` | 12, 13, 14, 15, 16… (API 31+) | `windowSplashScreenBackground` (SplashScreen API) |

The system picks the highest-matching qualifier at runtime. "Android 12" in the config name refers to when the SplashScreen API was introduced, not a version ceiling.

---

## 14. Observability & Analytics

Analytics and crash reporting are **infra-owned** — game implementors do not add Firebase calls. All events fire automatically from core infrastructure.

### Packages

| Package | Purpose |
|---|---|
| `firebase_analytics` | Event tracking, user identity, screen tracking |
| `firebase_crashlytics` | Fatal/non-fatal crash capture |

Firebase is **mandatory** — initialized unconditionally in `main()` alongside Supabase. Every deployment runs it.

### Architecture

```
lib/core/analytics/
├── analytics_service.dart           # Abstract interface — primitives only, no features/ imports
├── firebase_analytics_service.dart  # Firebase implementation
└── analytics_provider.dart          # analyticsServiceProvider (keepAlive: true)
```

`AnalyticsService` uses primitive types (`String`, `int`, `bool`) in all method signatures and never imports `features/` types. Call sites convert enums to strings (e.g., `_access.name`).

The provider returns a `FirebaseAnalyticsService` backed by `FirebaseAnalytics.instance`. The abstract interface keeps call sites decoupled from Firebase and makes the service straightforward to fake in tests.

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

`FlutterError.onError` catches framework-level errors (widget build failures, assertion errors). `PlatformDispatcher.instance.onError` catches isolate-level errors that escape the framework. Both are wired before `runApp` so no crash window exists at startup.

`firebase_options.dart` is generated once by `flutterfire configure` — do not hand-edit it.

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

Both `initialSession` and `signedIn` call `identify()` — without both, returning users (cold start with an existing session) would never be identified because Supabase fires `initialSession`, not `signedIn`, on startup.

`ref.read(currentUserProfileProvider.future).ignore()` starts the stale-while-revalidate cycle (SQLite cache restore + background network fetch) while the splash is still animating away. Because `currentUserProfileProvider` is `keepAlive: true`, the result is shared with all future watchers — no redundant fetch occurs when the Profile screen first opens. See §23 for the full persistence design.

`identify` maps to `FirebaseAnalytics.setUserId`; `reset` clears it with `setUserId(id: null)`.

### Screen Tracking

`FirebaseAnalyticsObserver` is registered on the GoRouter instance in `navigation_providers.dart`:

```dart
observers: [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
```

This automatically records a `screen_view` event on every route transition.

### Events

| Event | Firebase name | Properties | Source |
|-------|--------------|-----------|--------|
| `gameCreated` | `game_created` | `game_id`, `access`, `timing_mode`, `rated` (int 0/1) | `new_game_dialog.dart` after `createGame()` succeeds |
| `gameStarted` | `game_started` | `game_id`, `player_count` | `game_screen.dart` when game transitions to `active` |
| `gameFinished` | `game_finished` | `game_id` | `game_screen.dart` when outcomes first arrive (non-empty) |
| `forfeit` | `forfeit` | — | `game_screen.dart` after `forfeit_game` RPC succeeds |
| `joinByCode` | `join_by_code` | — | `join_game_screen.dart` after `join_game_by_code` RPC succeeds |
| `friendRequestSent` | `friend_request_sent` | — | `social_providers.dart` after `send_friend_request` RPC succeeds |
| `friendAccepted` | `friend_accepted` | — | `social_providers.dart` after `accept_friend_request` RPC succeeds |

**Note:** Firebase Analytics does not accept raw `bool` parameters. `rated` is sent as `int` (0 or 1).

### `game_started` and `game_finished` implementation

Both use `ref.listenManual` in `game_screen.dart`'s `initState`, not `ref.listen` in `build`. This is the correct Riverpod pattern for side effects that must not re-fire on widget rebuilds.

**`game_started`** fires only on a *witnessed* pre-game → active transition: `prev?.value?.status` must be `waiting` or `ready`. On the first emission after mounting, `prev?.value` is null, so opening an already-active game does not re-count the start. The player count is read via `ref.read(gamePlayersProvider(...))` before the handler invalidates that provider, so the count is still available at fire time:

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

**`game_finished`** fires only on a witnessed empty → non-empty outcomes transition, guarded by `prev?.value?.isEmpty != true`. This covers both re-fire paths: on first load (re-opening a finished game from History) `prev?.value` is null; on app-resume reloads `AsyncLoading` in Riverpod 3.x carries the previous non-empty `value`. In both cases the guard returns early:

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

1. Create a Firebase project at console.firebase.google.com — use the **Flutter** app type to register Android and iOS in one flow. Enable **Analytics** and **Crashlytics**.
2. `npm install -g firebase-tools && firebase login`
3. `dart pub global activate flutterfire_cli`
4. From the project root: `flutterfire configure` — select **Android** and **iOS** only.
   This generates `lib/firebase_options.dart`, `android/app/google-services.json`,
   `ios/Runner/GoogleService-Info.plist`, and `firebase.json`. All four are gitignored
   (instance-specific, not engine artifacts) and must never be committed.
5. Re-run `dart run build_runner build`.

### CI secrets (GitHub Actions)

The gitignored files must be supplied to CI as base64-encoded secrets. Encode locally and add to repo Settings → Secrets → Actions:

```bash
base64 -i lib/firebase_options.dart        | pbcopy  # → FIREBASE_OPTIONS_DART_BASE64
base64 -i android/app/google-services.json | pbcopy  # → GOOGLE_SERVICES_JSON_BASE64
# iOS (when iOS CI workflow is added):
base64 -i ios/Runner/GoogleService-Info.plist | pbcopy  # → GOOGLE_SERVICE_INFO_PLIST_BASE64
```

`firebase.json` is only used by the `flutterfire` CLI to know which project/app IDs to target on the next `flutterfire configure` run. It is not read during `flutter build appbundle` and does **not** need to be a CI secret.

The Android workflow decodes secrets before the build:

```yaml
- name: Decode Firebase config
  run: |
    echo "${{ secrets.FIREBASE_OPTIONS_DART_BASE64 }}" | base64 --decode > lib/firebase_options.dart
    echo "${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}" | base64 --decode > android/app/google-services.json
```

`firebase_options.dart` is also decoded in the `test` job (only this file — no `google-services.json` needed there) so `flutter analyze` can resolve the import.

With `google-services.json` present, the `firebase-crashlytics-gradle` plugin automatically uploads R8/ProGuard mapping during `flutter build appbundle`. Dart deobfuscation symbols (`--split-debug-info` output) are uploaded as a GitHub Actions artifact and may require an additional Gradle task — see §18.

### Files

| File | Role |
|---|---|
| `lib/firebase_options.dart` | Generated by `flutterfire configure` — gitignored, not hand-maintained |
| `android/app/google-services.json` | Android native Firebase config — gitignored |
| `ios/Runner/GoogleService-Info.plist` | iOS native Firebase config — gitignored |
| `firebase.json` | FlutterFire CLI project metadata — gitignored, not needed in CI |
| `lib/main.dart` | Firebase init + Crashlytics wiring |
| `lib/core/analytics/analytics_service.dart` | Abstract interface |
| `lib/core/analytics/firebase_analytics_service.dart` | Firebase implementation |
| `lib/core/analytics/analytics_provider.dart` | `analyticsServiceProvider` (keepAlive) |
| `lib/core/navigation/providers/navigation_providers.dart` | `FirebaseAnalyticsObserver` on GoRouter |

---

## 15. Store Integration

### In-App Updates (Android)

Implemented via [`in_app_update`](https://pub.dev/packages/in_app_update), which wraps the Play Core `AppUpdateManager`. The Play Core SDK is an OS-managed singleton — concurrent calls to `checkForUpdate()` are handled natively and do not require an application-level concurrency guard.

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

**Immediate vs flexible branching** — when `immediateUpdateAllowed` is `true`, the immediate path owns that branch entirely. If a game is active the method returns without starting a flexible update — an immediate update is never silently downgraded. The next `onResume` will retry.

**Mid-game gate** — `UpdateNotifier._isGameActive()` reads the current URI from `goRouterProvider.routerDelegate.currentConfiguration.uri`. Game routes live under `/game/`, which sits outside the shell navigator (root `parentNavigatorKey`), so the prefix check is reliable. No extra state is needed.

**Previously-downloaded updates** — a flexible update downloaded in a prior session surfaces via `UpdateAvailability.developerTriggeredUpdateInProgress + InstallStatus.downloaded`. This is checked first on every resume so the user is never left waiting for a redundant re-download.

**Snackbar placement** — `AppStartup` sits above `MaterialApp` and cannot resolve `ScaffoldMessenger`. `UpdateNotifier` exposes state instead; `ShellScaffold` (which has scaffold context) reacts via `ref.listen` and shows the snackbar. This keeps all UI in the widget tree and all lifecycle logic in the notifier.

#### Files

| File | Role |
|------|------|
| `lib/core/updates/update_notifier.dart` | `UpdateNotifier` notifier + `UpdateInstallStatus` enum |
| `lib/core/startup/app_startup.dart` | `AppLifecycleListener` wiring — calls `checkForUpdate()` on resume |
| `lib/core/navigation/widgets/shell_scaffold.dart` | `ref.listen(updateProvider, …)` → snackbar |

#### Packages

```yaml
dependencies:
  in_app_update: ^4.x.x   # wraps Play Core AppUpdateManager
```

iOS has no equivalent — `checkForUpdate()` returns early if `!Platform.isAndroid`.

---

### In-App Review

Implemented via [`in_app_review`](https://pub.dev/packages/in_app_review). The OS silently enforces its own quota (3× per year on both platforms) — no application-level gate beyond the modulo trigger is needed or appropriate.

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

**Win counting** — all wins count regardless of game type, timing mode, or rated status. The `OutcomeResult.win` check is the only gate applied at the call site in `GameScreen`.

**Trigger frequency** — a review prompt is requested every `_reviewEveryNWins` (5) wins. The OS may silently no-op the request if its own quota is exhausted; the counter keeps incrementing regardless so the next qualifying win will retry.

**Persistence** — `ReviewNotifier` uses `sharedPreferencesProvider` (a shared keepAlive provider in `lib/core/storage/shared_preferences_provider.dart`) so the same `SharedPreferences` instance is used across all consumers without duplicate initialization.

**Fire-and-forget** — `GameScreen` calls `onWin()` via `unawaited()` so a slow Play Store / App Store round-trip never delays the outcome UI.

**Deduplication** — `_onGameOutcomes` in `GameScreen` guards with `if (prev?.value?.isEmpty != true) return` (the same guard used for analytics): the win only counts on a witnessed empty → non-empty outcomes transition. Re-opening a finished game (`prev?.value` null on first load) and app-resume reloads (`AsyncLoading` carries the previous non-empty value in Riverpod 3.x) both return early, so revisiting an old win never inflates the review counter.

#### Files

| File | Role |
|------|------|
| `lib/core/review/review_notifier.dart` | `ReviewNotifier` — win counter + review request |
| `lib/core/storage/shared_preferences_provider.dart` | `sharedPreferencesProvider` — shared across `ReviewNotifier` and `ThemeController` |
| `lib/features/game/presentation/screens/game_screen.dart` | `_onGameOutcomes` → `unawaited(ref.read(reviewProvider.notifier).onWin())` |

#### Packages

```yaml
dependencies:
  in_app_review: ^2.x.x
```

The review dialog **never appears on simulators or debug builds** — always test on a real device through TestFlight or the Play Store internal track.

---

## 16. Haptic Feedback

Haptic feedback is **infra-owned** — game implementors do not import `flutter/services.dart` or choose which haptic to fire. All three feedback moments are wired automatically from `game_screen.dart`.

No package is required; `HapticFeedback` ships with `flutter/services.dart`.

### Feedback Moments

| Moment | Haptic | Source |
|--------|--------|--------|
| Valid action submitted | `lightImpact` | `_GameScreenState._submitAction` — fires before the RPC call (optimistic) |
| Win outcome arrives | `heavyImpact` | `_GameScreenState._maybeTriggerWinHaptic` — called from `_onGameOutcomes` alongside analytics and review |
| Invalid move attempted | `selectionClick` | `onInvalidAction` callback, wired by `_ActiveGameContent` and called by the game content widget |

### `onInvalidAction` Contract

`GameModule.buildContent()` receives an `onInvalidAction: VoidCallback` parameter provided by infra. Game content widgets call it whenever `BaseEngine.isValidAction` returns false on a player-initiated tap. Infra wires it to `HapticFeedback.selectionClick()`; game implementors do not choose the haptic.

```dart
onCellTap: (position) {
  final action = ActionData(position: position);
  if (engine.isValidAction(observation, pendingPlayers, action, myPlayerIndex)) {
    onAction(action.toJson());
  } else {
    onInvalidAction(); // infra fires selectionClick
  }
},
```

### Deduplication

`_maybeTriggerWinHaptic` is called from `_onGameOutcomes`, which is guarded by `if (prev?.value?.isEmpty != true) return`. This is the same guard used for analytics and in-app review: the haptic fires only on a witnessed empty → non-empty outcomes transition, never when re-opening a finished game or when `gameOutcomesProvider` reloads on app resume.

### Files

| File | Role |
|------|------|
| `lib/features/game/presentation/screens/game_screen.dart` | `_submitAction` → `lightImpact`; `_maybeTriggerWinHaptic` → `heavyImpact`; `_ActiveGameContent` → wires `onInvalidAction` to `selectionClick` |
| `lib/core/game/game_module.dart` | `buildContent` contract — declares `onInvalidAction: VoidCallback` |
| the game package's content widget (`presentation/<game>_content.dart`) | Calls `onInvalidAction()` in the rejection branch |

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

`/game`, `/join`, and `/profile` are declared with `parentNavigatorKey: rootNavigatorKey` so they render above the shell scaffold on the root navigator, not inside a branch.

### Navigation Method Semantics

| Method | Replaces stack? | Back behavior | When to use |
|---|---|---|---|
| `context.go(path)` | Yes — replaces entire stack | Exits app or lands at new root | Auth redirects, sign-out, branch switching |
| `context.push(path)` | No — adds to stack | Returns to previous screen | Any screen the user expects Back to undo |
| `context.pushReplacement(path)` | Replaces current entry only | Returns to entry below current | Transient screens (e.g. join spinner → game) |

### Back Behavior by Route

**Shell branches (Home, Lobby, History, Social, About, Settings):**
Each branch is a top-level destination. There is no `PopScope` intercepting back. Pressing Back from any branch exits the app with the system's predictive exit animation. Users switch branches via the drawer — Back is not a navigation gesture between branches.

**Game screen:**
Always reached via `context.pushNamed('game', ...)`. Back returns the user to whichever screen they came from (home, lobby, history). The predictive back gesture shows a peek of the source screen.

**Join screen (`/join/:code`):**
On success: `context.pushReplacementNamed('game', ...)` — atomically replaces the join spinner with the game screen so back from game does not land on a stuck spinner.
On error: `context.goNamed('home')` — safe fallback that works for both in-app entry and deep-link cold start (where no shell is in the stack).

**In-app join flow (from home dialog):**
`context.pushNamed('join', ...)` pushes the join screen. The join screen then `pushReplacementNamed` the game screen. Final stack: `[shell/home → game]`. Back from game → home.

### Predictive Back Gesture (Android 14+)

The activity declares `android:enableOnBackInvokedCallback="true"` in `AndroidManifest.xml`. This opts the app into the Android 14+ predictive back API.

GoRouter 17.x handles the back animation automatically:
- **Push routes** (game, join, profile): back shows a peek of the underlying route — correct behavior, no extra code needed.
- **Shell branches**: no route is beneath the branch on the navigator, so Android shows the standard exit-app animation — also correct for top-level destinations.

Do not remove `android:enableOnBackInvokedCallback="true"` from the manifest. Its absence silently disables predictive back for all users on Android 14+.

### Auth Redirect Pattern

The GoRouter `redirect` callback watches `authStateProvider`. When the auth state changes (sign-in or sign-out), `StreamListenable` notifies the router, which re-evaluates the redirect and navigates accordingly.

`routerProvider` is `keepAlive: true` so the GoRouter instance persists for the app lifetime and is never disposed between navigations.

### Unmatched Route Safety Net

`GoRouter` is configured with an `onException` handler that redirects any unmatched or malformed route to `/home`:

```dart
GoRouter(
  onException: (_, state, router) => router.go('/home'),
  …
)
```

This handles iOS Universal Links that the OS hands to the app but whose path does not match any declared route (e.g. a `/terms` deep-link intercepted by Universal Links that has no GoRouter route). Without this handler, GoRouter throws a `GoException` that surfaces as an unhandled exception crash.

### Notification-Triggered Navigation

Push notification taps emit a deep-link path from `NotificationService.navigationStream`.
`AppStartup` routes these via the `NotificationNavigation` extension on `GoRouter`
(defined in `app_router.dart`):

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

| File | Role |
|------|------|
| `lib/core/navigation/router/app_router.dart` | GoRouter config, `NotificationNavigation` extension |
| `lib/core/navigation/utils/stream_listenable.dart` | Bridges `Stream<T>` to `ChangeNotifier` for GoRouter `refreshListenable` |
| `lib/core/navigation/providers/navigation_providers.dart` | `routerProvider` — GoRouter singleton (`keepAlive: true`) |
| `lib/core/navigation/widgets/shell_scaffold.dart` | `NavigationDrawer` shell — no `PopScope`; back exits app |
| `android/app/src/main/AndroidManifest.xml` | `android:enableOnBackInvokedCallback="true"` opts into predictive back |

---

## 18. Android Release Hardening

Two complementary mechanisms harden the Android release build: R8 code shrinking at the Java/Kotlin layer and Dart-level obfuscation at the native binary layer. They are independent and both should be enabled.

### R8 Code Shrinking

R8 (the successor to ProGuard, default since Android Gradle Plugin 7.0) is enabled in `android/app/build.gradle.kts`:

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

`isShrinkResources` requires `isMinifyEnabled`. Together they reduce APK size and obfuscate the Java/Kotlin bytecode layer.

### ProGuard Rules (`android/app/proguard-rules.pro`)

Only libraries that do not ship their own consumer rules need explicit entries. Libraries that handle their own rules automatically (via `consumerProguardFiles` in their Maven artifacts or plugin build files) are intentionally omitted:

| Library | Why omitted |
|---------|-------------|
| Flutter engine | Rules added automatically by the Flutter Gradle plugin |
| `image_cropper` | Ships `consumer-proguard-rules.pro` (OkHttp + uCrop) |
| `google_sign_in` 7.x | Credential Manager + Play Services Maven artifacts include consumer rules |
| `in_app_update` / `in_app_review` | Google Play Core Maven artifacts include consumer rules |
| `supabase_flutter` | Pure Dart — no Android Java/Kotlin classes exist to protect |

Libraries with explicit rules:

```proguard
# Supabase: conservative keep in case a future version adds a native Android layer.
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**
```

### Dart Obfuscation

`--obfuscate` renames Dart symbols (class/method names → `a`, `b`, …) in the compiled native binary. `--split-debug-info` writes the mapping file to a separate directory so crash stack traces can be deobfuscated by Sentry or Crashlytics.

These are Flutter tool flags — they belong in the CI release build command, not in Gradle:

```bash
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/debug-info/android/

flutter build ipa --release \
  --obfuscate \
  --split-debug-info=build/debug-info/ios/
```

The `build/debug-info/` output is excluded from git via the existing `/build/` entry in `.gitignore`.

The Android CI workflow builds with these flags and handles symbol upload in two ways:

- **R8/ProGuard mapping** — uploaded automatically by the `firebase-crashlytics-gradle` plugin during the build, as long as `google-services.json` is present (decoded from `GOOGLE_SERVICES_JSON_BASE64` secret before the build).
- **Dart deobfuscation symbols** — uploaded as a GitHub Actions artifact. An explicit `uploadCrashlyticsSymbolFileRelease` Gradle task step is commented out in the workflow; enable it if Dart symbols do not appear automatically in the Firebase Crashlytics dashboard after the first build.

The iOS workflow (when added) mirrors this pattern with `--split-debug-info=build/debug-info/ios/` and `GOOGLE_SERVICE_INFO_PLIST_BASE64`.

---

## 19. Connectivity & Offline Handling

Connectivity detection is **infra-owned** — game implementors do not watch `connectivityProvider` or `isOfflineProvider` directly. All offline UI fires automatically from core infrastructure.

### Providers (`lib/core/connectivity/connectivity_provider.dart`)

| Provider | Type | Description |
|---|---|---|
| `connectivityProvider` | `Stream<List<ConnectivityResult>>` | Raw stream from `connectivity_plus`. Emits on every network interface change. |
| `isOfflineProvider` | `bool` | `true` when every result in the latest emission is `ConnectivityResult.none`. Returns `false` during the brief loading window before the first event so the UI never flash-shows "offline" on startup. |

**Caveat:** `connectivity_plus` reflects network interface availability (Wi-Fi associated, cell registered), not actual internet reachability. A device connected to a Wi-Fi router with no upstream internet will report online.

### Offline Banners

Two distinct banners use `StatusBanner` (`shared/widgets/status_banner.dart`) — a full-width slim container that sits outside `SafeArea` and bleeds edge-to-edge:

| Banner | Location | Condition | Content |
|---|---|---|---|
| `_OfflineBanner` | `ShellScaffold` | `isOfflineProvider == true` (any shell screen) | `wifi_off_rounded` icon + "No internet connection" — `errorContainer` colour scheme |
| `_ReconnectingBanner` | `GameScreen` | `(isOffline \|\| obsAsync is AsyncError \|\| gameAsync is AsyncError)` **and** game is non-terminal (waiting, ready, or active) | Spinner + "Reconnecting…" — `secondaryContainer` colour scheme |

Both banners are wrapped in `AnimatedSize` (200 ms, `Curves.easeInOut`). The layout pushes content down rather than overlaying it — nothing is obscured — but the height transition is animated so the layout shift is a smooth slide rather than an instant jump.

The game screen uses `_ReconnectingBannerSlot` (a `ConsumerWidget` leaf) to isolate connectivity rebuilds — when the connection drops or recovers, only the banner slot rebuilds, not the entire `_GameScreenState` tree.

`_ReconnectingBannerSlot` watches three sources: `isOfflineProvider`, `gameObservationProvider`, and `gameStreamProvider`. The `gameAsync is AsyncError` arm covers transient Supabase blips where the WebSocket drops but the device never goes fully offline — `isOfflineProvider` stays false, yet the stream has errored. `AsyncValue.value` is used to read the stale game status during error states (when `gameAsync` is `AsyncError`, the last-known `Game` is still accessible via `.value`) so the banner is never shown after a game ends.

### Network Error Humanization

`humanize()` (`lib/core/errors/error_messages.dart`) maps raw exceptions to user-friendly strings for snackbars. Network-failure errors are matched by `_isNetworkError()`, which checks for common patterns across platforms (`SocketException`, `Failed host lookup`, `Network request failed`, `Connection refused`, `XMLHttpRequest error`, `network_error`, `Unable to connect`) and returns `"Can't reach the server. Check your connection."`.

The login screen's `GoogleSignInButton` passes sign-in errors through `humanize()` so network failures produce the friendly string rather than a raw exception. All in-game action errors already used `humanize()` — the login screen is now consistent with that pattern.

### Realtime Channel Implementation

`GameRepository._channelStream<T>` is the shared helper that backs both `gameStream()` and `observationStream()`. It uses Supabase's lower-level channel API — `supabase.channel()` + `onPostgresChanges()` + `subscribe(callback)` — rather than the `.stream()` convenience method.

The key difference: `.stream()` closes its `StreamController` on `RealtimeSubscribeStatus.closed` (a plain WebSocket drop). Riverpod sees a completed stream, holds the last `AsyncData`, and never retries. `_channelStream` keeps the `StreamController` open across `closed`, trusting Supabase's auto-reconnect to fire `subscribed` again and calling `fetchCurrent()` at that point to guarantee fresh state.

**Status handling:**

| Status | Action |
|---|---|
| `subscribed` | `fetchCurrent()` via REST — initial load and every reconnect |
| `channelError` / `timedOut` | `controller.addError(…)` — Riverpod catches this and retries with exponential backoff |
| `closed` | No-op — Supabase auto-reconnects; next `subscribed` fires `fetchCurrent()` |

**`channel.unsubscribe()` vs `removeChannel()`:** `onCancel` calls `channel.unsubscribe()`, not `_client.removeChannel(channel)`. `removeChannel` contains a race-prone `if (channels.isEmpty) disconnect()` check — when two providers are simultaneously invalidated, both `removeChannel` calls may complete before new channels are added, momentarily emptying the list and disconnecting the WebSocket. `unsubscribe()` sends a leave push and the channel removes itself from `client.channels` via its own `_onClose → socket.remove(this)` callback, with no socket-level disconnect side-effect. This is the same cleanup path Supabase's own `.stream()` used internally.

**Riverpod retry:** Both `gameStreamProvider` and `gameObservationProvider` use a plain `@riverpod` annotation — no custom retry function. Riverpod 3.x `ProviderContainer.defaultRetry` applies: exponential backoff from 200 ms up to 6400 ms, up to 10 retries, for any `Exception` type (`Error` and `ProviderException` are not retried). Channel errors (`channelError`, `timedOut`) are all `Exception` types, so retry triggers automatically on every Realtime failure.

### Auto-Reconnect (`_onConnectivityChange`)

`GameScreen` registers a `ref.listenManual(isOfflineProvider, _onConnectivityChange)` listener in `initState`. On the offline → online transition it immediately invalidates both stream providers, bypassing Riverpod's retry backoff for the fast offline→online path:

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

Invalidating resets the retry counter and forces an immediate re-subscribe. The `_pendingExpiry` flag is set when a turn deadline fires while offline; the expiry nudge is deferred until connectivity is restored so the server call can succeed.

No status gate is applied — both streams are invalidated regardless of game status (waiting, ready, active). The streams auto-dispose when their provider is no longer watched, so invalidating during pre-game is harmless.

### Observation Snackbar (`_onObservation`)

`_onObservation` is registered via `ref.listenManual` in `initState` and uses a single `switch` statement with a `mounted` guard at the top:

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

`_errorSnackBarShown` is a debounce flag covering both the reconnecting and the terminal ("This game has ended.") snackbars — without it, Riverpod's retry cycle would re-show the snackbar on every failed attempt. `clearSnackBars()` explicitly dismisses it on the first successful observation after reconnect; resetting the flag alone is insufficient because the visible snackbar would otherwise persist until its own 10-second `duration` expires.

### Stale-Data Fallback in `build()`

`_GameScreenState.build()` uses a guarded `switch` on `gameAsync` so the game UI is preserved during Riverpod retry cycles:

```dart
switch (gameAsync) {
  _ when gameAsync.value != null => _GameBody(game: gameAsync.value!, …),
  AsyncError(:final error)      => _ErrorState(error: …, onRetry: _retryConnection),
  _                             => const CircularProgressIndicator(),
}
```

`gameAsync.value` is non-null for both `AsyncData` (normal) and `AsyncError` with a previous value (Riverpod 3.x carries stale data in `AsyncError.value`). The first arm matches both, keeping the board visible while the `_ReconnectingBanner` communicates the reconnecting state. The `AsyncError` arm (error with no stale data) only fires on a cold-start failure before any data has arrived.

### Files

| File | Role |
|---|---|
| `lib/core/connectivity/connectivity_provider.dart` | `connectivityProvider` + `isOfflineProvider` |
| `lib/shared/widgets/status_banner.dart` | `StatusBanner` — slim full-width banner primitive |
| `lib/core/navigation/widgets/shell_scaffold.dart` | `_OfflineBanner` — shown on all shell screens |
| `lib/features/game/data/game_repository.dart` | `_channelStream<T>` — Realtime channel helper; `gameStream()` and `observationStream()` |
| `lib/features/game/providers/game_providers.dart` | `gameStreamProvider` + `gameObservationProvider` — plain `@riverpod` (inherits `defaultRetry`) |
| `lib/features/game/presentation/screens/game_screen.dart` | `_ReconnectingBannerSlot`, `_ReconnectingBanner`, `_onConnectivityChange`, `_onObservation` |

---

## 20. Push Notifications (FCM)

Push notifications are **infra-owned** — game implementors do not call the notification service or register FCM tokens. All wiring happens automatically in `AppStartup`.

### Packages

| Package | Purpose |
|---|---|
| `firebase_messaging` | FCM token registration, background/foreground message delivery |
| `flutter_local_notifications` | Shows a notification banner on Android/iOS when the app is foregrounded |

### Architecture

```
lib/core/notifications/
├── firebase_notification_service.dart  # FCM implementation
└── notification_provider.dart          # notificationServiceProvider (keepAlive)
                                        # notificationPermissionStatusProvider (auto-dispose)
```

`AppStartup.initState` registers on `navigationStream` first (stored in `_notificationSub`), then calls `initialize()` inside a try/catch. The listener-before-init order ensures the initial-message path (terminated-state tap) is never missed on a broadcast stream.

`notificationPermissionStatusProvider` fetches the current `AuthorizationStatus` on demand and is **not** keepAlive — it auto-disposes. `AppLifecycleListener.onResume` in `AppStartup` calls `ref.invalidate(notificationPermissionStatusProvider)` so the Settings screen always reflects the current OS permission state after the user returns from system Settings.

### What `initialize()` does

1. Creates three Android notification channels (see §Notification categories).
2. Calls `setForegroundNotificationPresentationOptions` so iOS shows banners while
   foregrounded.
3. Initialises `flutter_local_notifications` for foreground banners.
4. Requests OS permission once, gated by a `SharedPreferences` flag — dialog
   appears only on first launch.
5. Gets the FCM token (passing `vapidKey` on web) and upserts it via
   `upsert_device_token(p_token, p_platform)` RPC.
6. Subscribes to `onTokenRefresh` to re-upsert when FCM rotates the token.
7. `FirebaseMessaging.onMessage` → shows a local notification banner, except
   `your_turn` notifications for the game the user is currently viewing: the
   handler reads `goRouterProvider`'s current URI and suppresses the banner
   if the user is already on `/game/{gameId}` matching the notification's
   deep link. Background delivery is unaffected — the OS renders those banners
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

Runs in an isolated context for terminated-state messages. Re-initialises Firebase
so the plugin messenger is available; takes no other action — the OS renders the
notification from the `notification` payload automatically.

### Notification categories

Three Android channels give users per-category system-level control. iOS uses
`InterruptionLevel` to match priority:

| Channel id | Name | Importance | iOS level | Triggered by |
|---|---|---|---|---|
| `your_turn` | Your Turn | High | `timeSensitive` | `observations` INSERT or UPDATE |
| `game_invites` | Game Invites | Default | `active` | `games` INSERT (`access = 'friends'`) |
| `social_notifications` | Social & Friends | Low | `active` | `relationships` INSERT |

`your_turn` is the default FCM channel (`AndroidManifest.xml`) so system-delivered
background notifications fall back to it when no `channelId` is specified.

### `device_tokens` table

| Column | Type | Notes |
|---|---|---|
| `user_id` | uuid | FK → `auth.users`, cascade delete |
| `token` | text | FCM registration token (unique per install) |
| `platform` | text | `'ios'`, `'android'`, or `'web'` |
| `updated_at` | timestamptz | Refreshed on every upsert |
| PK | (user_id, token) | Composite — multiple devices per user supported |

Multiple devices for the same user each get their own row. All rows are notified
on every event.

### Token lifecycle

**Registration**: `initialize()` upserts the current token on every app start.
`onTokenRefresh` re-upserts on rotation — the old row remains until the monthly
cleanup removes it.

**Sign-out**: `AuthController.signOut` calls `deleteCurrentToken()` before clearing
the session — the token is deleted from `device_tokens` and invalidated with FCM
so the install stops receiving notifications immediately.

**Uninstall**: Undetectable client-side. The monthly pg_cron job (see below) removes
tokens not refreshed in 90 days. FCM rotates active-app tokens periodically, so a
90-day-stale token reliably means the app is gone or the account is abandoned.
Failed FCM calls to stale tokens are silent no-ops — no cost, no error surfaced.

**Monthly cleanup** (defined in the migration):
```sql
SELECT cron.schedule(
  'cleanup-stale-device-tokens',
  '0 3 1 * *',   -- 3 am on the 1st of each month
  $$DELETE FROM public.device_tokens WHERE updated_at < now() - interval '90 days'$$
);
```

### FCM message data payload

| Field | Values | Purpose |
|---|---|---|
| `deep_link` | `/game/<id>` (your_turn), `/join/<short_code>` (game_invite), `/social` (friend_request) | Navigation on tap |
| `category` | `your_turn`, `game_invite`, `friend_request` | Android channel routing |

### Server-side notification dispatch

Postgres triggers call FCM directly via `pg_net` using a **cached OAuth token**,
avoiding a per-notification edge function invocation.

**Token-cache pattern**

FCM HTTP v1 requires a short-lived Google OAuth2 bearer token (JWT/RS256). Postgres
cannot sign RS256 natively, so a lightweight edge function refreshes the token on a
schedule and stores it in `private.app_config`:

```
pg_cron every 50 min → refresh-fcm-token edge function
  → exchanges FIREBASE_SERVICE_ACCOUNT_JSON for a Google access token
  → stores token and project ID in private.app_config
      ('fcm_access_token', 'firebase_project_id')
Postgres triggers → read cached token → pg_net POST to FCM HTTP v1
```

Google access tokens live 60 minutes; refreshing every 50 minutes keeps the cached
token valid. At ~30 edge function calls/day this is well within Supabase free-tier
limits regardless of notification volume.

**Triggers**

| Trigger | Table | Condition | Notifies |
|---|---|---|---|
| `notify_your_turn` | `observations` | INSERT or UPDATE: `player_index` enters `pending_players` (INSERT covers `start_game`'s version-0 rows, so initially-pending players get the first-move push) | `observations.user_id` |
| `notify_game_invite` | `games` | INSERT: `access = 'friends'` (public games are lobby-discoverable, not pushed — pushing every public game to all friends would be spam) | All accepted friends of `created_by` |
| `notify_friend_request` | `relationships` | INSERT: `status = 'pending'` | The user who is not `initiated_by` |

`private.send_push_notification` loops over `device_tokens` for the target user
and fires one `net.http_post` per device. Zero rows = no HTTP calls. If the cached
token is absent (FCM not configured), it emits a `WARNING` and returns early — all
sends degrade gracefully in local dev.

**Trigger type and performance**

All three triggers are `AFTER … FOR EACH ROW`. They fire after the row is durably written but still within the same transaction — the write call doesn't return to the client until the trigger body finishes. This is not a concern in practice because `pg_net`'s `net.http_post` is non-blocking: it enqueues the HTTP request in a background worker and returns a `request_id` immediately without waiting for FCM to respond. The trigger body is a few indexed `SELECT`s plus the non-blocking enqueue — a few milliseconds, not a meaningful hit to game write throughput. `AFTER` (not `BEFORE`) is correct: there is no point notifying a player before the write has committed.

**`pg_net` extension**

`pg_net` is pre-installed and always enabled in Supabase. Migrations include `CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions` — the `WITH SCHEMA extensions` qualifier places the extension in the `extensions` schema rather than `public`, avoiding the Supabase linter warning about public-schema extensions. `pg_cron` requires explicit enabling via `CREATE EXTENSION IF NOT EXISTS pg_cron` (no schema qualifier — it manages its own `cron` schema).

### Security

`public.store_fcm_access_token` must live in the `public` schema because `supabase.rpc()` in the edge function only reaches PostgREST-exposed functions — `private` schema functions are invisible to the API. It is protected by:

```sql
REVOKE EXECUTE ON FUNCTION public.store_fcm_access_token(text, text)
  FROM PUBLIC, anon, authenticated;
```

`service_role` (the role the edge function authenticates as) retains `EXECUTE` and is unaffected by this revoke. Clients using `anon` or `authenticated` cannot invoke it. This is the same pattern as `public.apply_rating_updates` in the rating system. Internal helpers (`private.send_push_notification`, the trigger functions) live in the `private` schema and are never exposed via PostgREST — no REVOKE needed for those.

### Android notification icon

Android API 21+ ignores colour in notification icons — the system composites the icon's alpha channel against its own tint (white on a dark background). Using the full-colour launcher icon (`@mipmap/ic_launcher`) causes the system to render a solid white box.

The correct approach is a monochrome silhouette vector drawable at `android/app/src/main/res/drawable/ic_notification.xml`. It is referenced in three places:

| Location | Usage |
|---|---|
| `AndroidManifest.xml` — `com.google.firebase.messaging.default_notification_icon` meta-data | FCM-delivered notifications (background and terminated state) |
| `AndroidInitializationSettings('@drawable/ic_notification')` in `firebase_notification_service.dart` | `flutter_local_notifications` foreground banners |
| `AndroidNotificationDetails(icon: '@drawable/ic_notification')` in `_showForegroundNotification` | Per-notification override (ensures consistency across all show calls) |

The drawable is a `<vector>` XML, not a raster PNG — no per-density variants are needed, Android scales it perfectly at any size. The shape should be a simplified monochrome silhouette of the app's launcher icon foreground.

`flutter_launcher_icons` does not support notification icon generation (it generates launcher icons only). `ic_notification.xml` is a one-time manually-maintained asset — it only needs to change if the app rebrands.

### `_NotificationCategory` strictness

`_NotificationCategory.fromString` throws `ArgumentError` for any unknown or missing `category` field in the FCM data payload — it never returns `null` and has no fallback channel. Every notification sent from the server must include an explicit, known `category`. This is intentional: a silent fallback would hide misconfigured server-side triggers, making bugs invisible until a user reports missing notifications.

### iOS setup (one-time per deployment)

1. Xcode → Runner target → Signing & Capabilities → add **Push Notifications**
   and **Background Modes** (check Remote notifications).
2. Firebase Console → Cloud Messaging → Apple app configuration → upload APNs `.p8` key.
3. `flutterfire configure` generates `ios/Runner/GoogleService-Info.plist` — gitignored.
   For iOS CI, encode it and add as a GitHub Actions secret:
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
   importScripts('https://www.gstatic.com/firebasejs/10.x.x/firebase-app-compat.js');
   importScripts('https://www.gstatic.com/firebasejs/10.x.x/firebase-messaging-compat.js');
   firebase.initializeApp({ /* same config as firebase_options.dart */ });
   firebase.messaging().onBackgroundMessage((payload) => {
     self.registration.showNotification(payload.notification.title, {
       body: payload.notification.body,
       icon: '/icons/Icon-192.png',
     });
   });
   ```
4. The Flutter code already passes `vapidKey: kIsWeb ? Env.firebaseVapidKey : null`
   to `getToken()` and detects `'web'` platform in `_upsertToken`. No further code
   changes needed — setting the env var is sufficient to activate web tokens.

### OAuth token lifetime

Google access tokens obtained via the JWT bearer grant (RFC 7523) are **contractually** 3600 seconds. The edge function requests `exp: now + 3600`; Google always honors it for service accounts. The 50-minute cadence provides a 10-minute buffer and is not an assumption — the 3600-second limit is documented by Google and enforced by their token endpoint.

**Failure mode**: if a pg_cron invocation fails (edge function crash, network error), the next retry fires 50 minutes later. Two consecutive failures leave the cached token ~100 minutes old — stale. `send_push_notification` does not check token freshness, so FCM calls made with a stale token will be rejected by Google silently (pg_net is fire-and-forget; errors are not surfaced). Notifications are lost until the next successful refresh. In practice this is rare — a pg_cron miss is a Supabase infrastructure event, not application logic.

### Supabase edge function secrets

`refresh-fcm-token` requires three secrets. These are edge function environment variables, not Vault secrets — they are set once per project via the CLI or Dashboard and are invisible to client code.

Only two fields from the service account are used — `client_email` (the JWT issuer) and `private_key` (for RS256 signing). The full JSON blob is never needed.

**Obtaining the values:**

1. Firebase Console → Project Settings (gear icon) → **Service accounts** tab.
2. Click **Generate new private key** → **Generate key** → a `.json` file downloads.
3. Open the file and copy only:
   - `client_email` — looks like `firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com`
   - `private_key` — the full PEM block including `-----BEGIN PRIVATE KEY-----` header/footer
4. Delete the downloaded file — it grants Firebase Admin access and should never be stored.

**Setting the secrets:**

```bash
# SERVERLESS_SECRET must match the value already in Supabase Vault (see §8 Production Configuration).
supabase secrets set SERVERLESS_SECRET=<same-value-as-vault>

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

**Local dev**: `refresh-fcm-token` will not work without real Firebase credentials. This is expected — `send_push_notification` degrades gracefully with a `WARNING` when the cached token is absent, so local play is unaffected. Do not add placeholder Firebase values to `seed.sql`.

After setting secrets, deploy all functions (see §21).

| Secret | Used by |
|---|---|
| `FIREBASE_CLIENT_EMAIL` | `refresh-fcm-token` — JWT issuer claim for Google OAuth2 token exchange |
| `FIREBASE_PRIVATE_KEY` | `refresh-fcm-token` — RS256 signing key for the JWT |
| `FIREBASE_PROJECT_ID` | `refresh-fcm-token` — stored in `private.app_config` so triggers can build the FCM endpoint URL |
| `SERVERLESS_SECRET` | `refresh-fcm-token` — same shared secret as `update-ratings`; Postgres reads it from Vault as `serverless_secret` |

### Files

| File | Role |
|---|---|
| `lib/core/notifications/firebase_notification_service.dart` | FCM implementation |
| `lib/core/notifications/notification_provider.dart` | `notificationServiceProvider` (keepAlive) + `notificationPermissionStatusProvider` (auto-dispose, invalidated on resume) |
| `lib/core/startup/app_startup.dart` | Calls `initialize()`, stores `_notificationSub`, routes `navigationStream` taps via `navigateFromNotification` |
| `android/app/src/main/res/drawable/ic_notification.xml` | Monochrome silhouette vector — used as the Android notification icon for both foreground (`flutter_local_notifications`) and background/terminated-state (FCM direct delivery) notifications |
| `android/app/src/main/AndroidManifest.xml` | `com.google.firebase.messaging.default_notification_icon` meta-data points to `@drawable/ic_notification` |
| `supabase/migrations/20260518081308_device_tokens.sql` | `device_tokens` table, `upsert_device_token`/`delete_device_token` RPCs, monthly cleanup |
| `supabase/migrations/20260518091300_notification_triggers.sql` | `send_push_notification`, `store_fcm_access_token`, three notification triggers, `refresh-fcm-token` pg_cron job |
| `supabase/functions/refresh-fcm-token/index.ts` | OAuth token refresh (called by pg_cron every 50 min) |

---

## 21. Edge Functions

### Function inventory

| Function | Trigger | Purpose |
|---|---|---|
| `update-ratings` | pg_net POST from `notify_rating_update` trigger on rated game finish | Runs OpenSkill, writes `player_ratings` + `rating_history` via `apply_rating_updates` RPC |
| `refresh-fcm-token` | pg_cron every 50 min | Exchanges `FIREBASE_SERVICE_ACCOUNT_JSON` for a Google OAuth2 token, stores it in `private.app_config` for Postgres triggers to use |

Both functions verify the `x-webhook-secret` header against `SERVERLESS_SECRET` before doing any work.

### Local development

The Supabase CLI serves all functions locally:

```bash
supabase functions serve
```

Secrets for local serving live in `supabase/functions/.env.local` (not committed, but the file already exists with the local dev value):

```
SERVERLESS_SECRET=local-dev-secret   # matches seed.sql Vault value
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically by the CLI — do not add them to `.env.local`.

**Firebase secrets** (`FIREBASE_SERVICE_ACCOUNT_JSON`, `FIREBASE_PROJECT_ID`) are intentionally absent from `.env.local`. `refresh-fcm-token` will fail when pg_cron calls it locally, but `send_push_notification` degrades gracefully (WARNING + early return) when the cached token is absent. Push notifications simply don't fire in local dev.

**Firebase app** (`firebase_options.dart`): Firebase is mandatory — the app will not compile without this file. Run `flutterfire configure` once when first setting up the project, even for local development. The generated file connects to a real Firebase project; Analytics and Crashlytics events will appear there during local dev runs.

### Production deployment

Set all secrets first (§8 for `SERVERLESS_SECRET` + Vault; §20 for Firebase secrets), then deploy all functions in one command:

```bash
supabase functions deploy
```

No arguments = deploys every function in `supabase/functions/`. Re-run this command any time function code changes. Secrets do not need to be re-set on redeploy — they persist in the project.

There is no automated CD for edge functions in the CI workflow. Deployment is a manual step performed alongside database migrations when releasing changes that touch function code.

---

## 22. Account Deletion

Account deletion is **infra-owned**. It is exposed to the client via the `delete_account()` RPC and surfaces in the UI as a destructive action in Settings (bottom of the screen, `colorScheme.error` styling, confirmation dialog).

### Client-Side Flow

```
AuthController.deleteAccount()
  1. deleteUserData(ref, userId)             ← clears SQLite profile cache (unsafe_forever never expires on its own)
  AuthService.deleteAccount()
  2. Best-effort avatar removal from storage ('avatars' bucket, object name = userId)
  3. supabase.rpc('delete_account')          ← the single DB call
  4. supabase.auth.signOut()                 ← best-effort; swallow errors

AuthController.signOut()
  1. deleteUserData(ref, userId)             ← clears SQLite profile cache
  2. notificationService.deleteCurrentToken() ← best-effort FCM token removal
  3. supabase.auth.signOut()
```

Avatar removal is done client-side first because storage is separate from the DB transaction — after `auth.users` is deleted the client has no credentials to call the Storage API. If it fails (avatar not found, network error), deletion continues.

`deleteUserData` deletes the user-scoped SQLite keys (`profile_<userId>`, `friendships_<userId>`) before the session ends. This is necessary because `StorageCacheTime.unsafe_forever` never expires automatically — without explicit deletion, a subsequent login as a different account on the same device could theoretically read stale keys. See §23 for the full persistence design.

`signOut()` after a successful `delete_account` call will likely fail (the auth session is already gone) — those errors are caught and silently dropped. Navigation back to the auth screen is driven by the existing `authStateChangesProvider` listener reacting to the session becoming null.

### Server-Side Flow (`private.delete_account`)

Runs as a single transaction under the caller's auth identity. All game cleanup happens **before** `DELETE FROM auth.users` so that `auth.uid()` remains valid throughout.

```
private.delete_account()
  │
  ├── FOR each waiting/ready game the user CREATED:
  │     private.cancel_game(game_id)        ← sets status = 'aborted'
  │
  ├── FOR each waiting/ready game the user JOINED but did not create:
  │     private.leave_game(game_id)         ← compacts player_index values,
  │                                            transitions ready→waiting if needed
  │
  ├── FOR each active game the user is in:
  │     private.forfeit_game(game_id)   ← acquires its own FOR UPDATE lock
  │       └── game_handle_system_action('forfeit', …)
  │           └── commit_action(…)
  │               ├── INSERT game_states (new version)
  │               ├── INSERT actions (type='system', player_index=forfeiting seat)
  │               ├── finish_game → INSERT game_outcomes, UPDATE games.status='finished'
  │               │     └── on_game_finished_update_ratings trigger fires
  │               │           └── net.http_post → update-ratings edge function (async)
  │               └── update_all_observations (fans out per-player observations)
  │
  └── DELETE FROM auth.users WHERE id = v_user_id
        └── CASCADE → public.users
              ├── CASCADE → user_profiles           (deleted)
              ├── CASCADE → relationships            (deleted — both sides)
              ├── CASCADE → player_ratings           (deleted)
              ├── CASCADE → rating_history           (deleted)
              ├── SET NULL → games.created_by        (preserved, creator anonymized)
              ├── SET NULL → participants.user_id    (preserved, seat row retained)
              ├── SET NULL → game_outcomes.user_id   (preserved, outcome anonymized)
              ├── SET NULL → actions.user_id         (preserved, audit log retained)
              └── CASCADE → observations.user_id     (deleted — no longer needed)
        └── CASCADE → device_tokens (auth.users fk)  (deleted)
```

#### Why `cancel_game` / `leave_game` before the cascade?

A plain `DELETE FROM auth.users` would SET NULL on `participants.user_id` and leave orphaned lobby rows. `cancel_game` and `leave_game` run the proper cleanup logic: compacting `player_index` values, transitioning game status, and preserving lobby integrity for other players. The explicit loop is necessary because the cascade knows nothing about these invariants.

#### Why no version handshake around `forfeit_game`?

`forfeit_game` takes no `expected_version` — forfeiting is an unconditional intent. It acquires its own `FOR UPDATE` lock on `games` and reads the latest `game_states` row under that lock, so the committed action is always correctly ordered even if other players act concurrently.

### What is Preserved

Game history is preserved for other players and for future analysis:

| Data | Fate | Reason |
|------|------|--------|
| `game_states` rows | **Preserved** (game ON DELETE CASCADE does not fire; the game row stays) | Immutable append-only history; needed for replay and audit |
| `actions` rows | **Preserved** — `user_id` SET NULL; `player_index` intact | Audit log and replay attribution via `player_index` |
| `game_outcomes` rows | **Preserved** — `user_id` SET NULL; `player_index`, `result`, `placement` intact | Analytics and rating history for other players |
| `participants` rows | **Preserved** for finished games — `user_id` SET NULL | `gamePlayersProvider` needs the seat to display "Deleted User" |
| `player_ratings` | **Deleted** (CASCADE) | No identity → no leaderboard entry |
| `rating_history` | **Deleted** (CASCADE) | Personal audit log; meaningless without an account |
| `user_profiles` | **Deleted** (CASCADE) | Personal data |
| `relationships` | **Deleted** (CASCADE from both sides) | Social graph |
| `observations` | **Deleted** (CASCADE) | Derived data; regenerable from `game_states` via `get_replay` |
| `device_tokens` | **Deleted** (CASCADE from auth.users) | No account → no push delivery |
| Avatar file | **Deleted** (client-side before RPC) | Storage is not in the DB transaction |

### Rating Update Race Condition

The `on_game_finished_update_ratings` trigger fires synchronously during `forfeit_game` (when `games.status` transitions to `'finished'`). The trigger **reads `game_outcomes.user_id` at trigger time**, before the cascade sets it to NULL, and bundles it into the `net.http_post` payload. The HTTP call fires asynchronously after the transaction commits.

By commit time, `public.users` has been deleted (the cascade ran in the same transaction). The `apply_rating_updates` RPC — called by the edge function — guards against this:

```sql
IF v_user_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM public.users WHERE id = v_user_id
) THEN
  CONTINUE;  -- skip deleted user, other players still get their update
END IF;
```

The deleted player's rating row has already been CASCADE-deleted. The surviving players in the same game receive their rating updates normally.

### Dart-Side Null Handling

After deletion, `participants.user_id` and `participants.bot_id` are both NULL for the deleted player's seat on finished games. `gamePlayersProvider` handles this explicitly:

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

`GamePlayer.isDeleted` is the correct guard for UI decisions — never inspect `PlayerInfo.id` directly. The synthetic ID's only role is to give each deleted seat a distinct widget key; it is not a database UUID and must not be passed to identity lookups or `PlayerProfileSheet.show`. `displayName` is `'Deleted User'` — shown anywhere the player's name appears in the game screen or history.

### Settings UI

`_DeleteAccountTile` — placed at the bottom of the Settings screen with no section label, `colorScheme.error` styling throughout (icon, title, chevron).

`_DeleteAccountDialog` — `AlertDialog` with a plain-language warning ("permanently deletes your account, all your games, and your ratings. This cannot be undone."), a Cancel button, and a filled Delete button styled with `colorScheme.error`. While the RPC is in flight the button shows a 16 × 16 `CircularProgressIndicator` and both buttons are disabled. On error a `SnackBar` surfaces the message and re-enables the button. On success the dialog is popped — the `authStateChangesProvider` listener drives navigation to the sign-in screen.

### Terms & Privacy Links

Terms of Service and Privacy Policy links in the Settings screen open using `LaunchMode.inAppBrowserView` (`url_launcher`), which maps to `SFSafariViewController` on iOS and Chrome Custom Tabs on Android. This mode is required on iOS to prevent Universal Links interception — without it, iOS would hand the URL back to the app's GoRouter, which throws a `GoException` because neither `/terms` nor `/privacy` are declared routes. `inAppBrowserView` bypasses the Universal Links handler entirely, keeping the browser session inside the app without router involvement.

---

## 23. Local Persistence

### Goal

Eliminate cold-start spinners for data that is already known and unlikely to have changed meaningfully since the last session. The first paint should show real data; background refreshes update silently.

### Technology

`riverpod_sqflite` provides a `JsonSqFliteStorage` backend for Riverpod 3.x's experimental `persist()` API. A single SQLite database (`riverpod.db`) stores all persisted provider state as JSON strings, keyed by a string. One database connection is opened at startup and shared by all providers.

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

`storageProvider` is a **function-based `FutureProvider`**, not an `AsyncNotifier`. It opens a resource once and never mutates state — `AsyncNotifier` is for mutable state and would be the wrong abstraction here.

`deleteUserData` is a **free function**, not a method on a class. This avoids a circular import: `auth_providers.dart` calls `deleteUserData`, `profile_providers.dart` imports `auth_providers.dart`, and `deleteUserData` needs `profileCacheKey` — putting all three in `core/storage` breaks the cycle.

Cache key helpers are intentionally kept in this file rather than in their respective provider files for the same circular-import reason.

### Stale-While-Revalidate Pattern

Persisted providers race their SQLite restore against the network fetch simultaneously:

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

`persist()` is called **without awaiting** it. Awaiting it would serialize the two fetches and eliminate the performance benefit. The internal `didChange` guard prevents stale SQLite data from overwriting a fresher network result.

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

| Decision | Rationale |
|---|---|
| `keepAlive: true` | Provider never auto-disposes; navigating away and back does not re-fetch |
| `@JsonPersist()` | Code-generates a typed `persist()` method using `UserProfile.fromJson`/`toJson`; no hand-written encode/decode |
| `key: profileCacheKey(user.id)` | User-scoped: different accounts on the same device never share cached data |
| `StorageCacheTime.unsafe_forever` | Cache never expires on its own; explicit `deleteUserData` on sign-out handles eviction |
| `destroyKey: '1'` | Bump this string whenever `UserProfile`'s JSON schema changes incompatibly — old cached entries are discarded and a fresh fetch runs |

`@JsonPersist()` works because `UserProfile` is a `@freezed` class with `fromJson`/`toJson`. The generator reads those methods and produces a `persist()` extension that handles the `String` encode/decode that `JsonSqFliteStorage` requires.

### Cache Eviction

`StorageCacheTime.unsafe_forever` means entries survive until explicitly deleted. Eviction must be triggered at the right moment:

- **Sign-out** (`AuthController.signOut`): `deleteUserData(ref, userId)` before `signOut()` — the userId is read while the session is still active.
- **Account deletion** (`AuthController.deleteAccount`): same pattern, same reason.
- **`playerInfoCacheProvider` entries are NOT cleared on sign-out.** Player identity (username, displayName, avatarUrl) is public data — a different account on the same device benefits from the same cache and seeing stale-then-fresh data for other players is harmless.
- **Profile mutations** (`uploadAvatar`, `updateProfileFields`): `CurrentUserProfile` calls `ref.invalidate(playerInfoCacheProvider(id: userId))` after each successful save so game screens and social views reflect the change immediately.

**Why per-key deletion, not file deletion?** Calling `ref.invalidate(storageProvider)` while `currentUserProfileProvider` is watching the storage provider would trigger an immediate rebuild — `currentUserProfileProvider.build()` would re-call `ref.watch(storageProvider.future)`, re-opening the database file before deletion could finish. Per-key `storage.delete(key)` avoids this race entirely.

### `Friendships`

`Friendships` holds three `Mutation` objects as static fields. Widgets call `Friendships.send(playerId).run(...)` etc. — each playerId gets an independent in-flight state machine. The mutations live on the class (not in a separate file) so the label and the notifier methods that execute them are co-located.

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

`Friendship` is a `@freezed` class with `fromJson`/`toJson`, so `@JsonPersist()` works without any model changes. `RelationshipStatus` is a plain Dart enum; `json_serializable` serialises it as its string name.

**Derived providers** (`acceptedFriends`, `pendingRequests`, `sentRequests`, `friendStatus`) are auto-dispose `FutureProvider`s that watch `friendshipsProvider.future` — they need no persistence of their own. When `friendshipsProvider` updates (from cache or network), all derived providers rebuild automatically. `friendStatusProvider(targetId: id)` derives a `FriendStatus` enum value (`friends`, `incomingPending`, `outgoingPending`, `none`) for a specific player; `FriendActions` uses this to decide which button(s) to render.

**Notification-driven invalidation.** The shell-scaffold badge (`pendingRequests`) and the Requests tab are the primary surfaces a user checks after tapping a friend-request notification. If the Social screen is already mounted when the notification arrives, `initState` is never called — the widget is alive and stale. To close this gap, `AppStartup._onNotificationNavigation` invalidates `friendshipsProvider` before navigating whenever the destination path starts with `/social`:

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

Invalidation fires before `navigateFromNotification`, so the provider starts refetching while the navigation transition animates. With persistence, the cached list renders instantly; the fresh list arrives silently by the time the animation completes.

### What Is and Is Not Persisted

| Provider | Persisted | Reason |
|---|---|---|
| `currentUserProfileProvider` | Yes | Own profile; cold-start UX |
| `playerInfoCacheProvider(id)` | Yes | Public player identity; eliminates per-player spinners on cold start |
| `friendshipsProvider` | Yes | Social list; stale-while-revalidate + notification-driven invalidation |
| `playerRatingsProvider` | No | Rating data; excluded by design |
| `activeGamesProvider` | No | Real-time data; staleness would be misleading |

### Pre-Warm at Auth

`AppStartup._onAuthStateChange` fires `ref.read(currentUserProfileProvider.future).ignore()` on `initialSession` and `signedIn` events. This starts the stale-while-revalidate cycle (SQLite restore + network fetch) while the splash screen is still animating away. Because the provider is `keepAlive`, the result is shared with all future watchers — no second fetch occurs when the Profile screen opens.

### Schema Migration

If `UserProfile` fields change in a way that makes cached JSON unparseable, bump `destroyKey` from `'1'` to `'2'` (or any new string). All existing entries for that key are discarded on the next launch and a fresh network fetch populates the cache. This is the only migration path — there is no incremental JSON migration mechanism.

### Files

| File | Role |
|---|---|
| `lib/core/storage/storage_provider.dart` | `storageProvider`, `profileCacheKey`, `friendshipsCacheKey`, `deleteUserData` |
| `lib/core/storage/storage_provider.g.dart` | Generated by `riverpod_generator` |
| `lib/features/profile/providers/profile_providers.dart` | `CurrentUserProfile` — `keepAlive`, `@JsonPersist()`, `persist()`; invalidates `playerInfoCacheProvider` on mutations |
| `lib/features/social/providers/social_providers.dart` | `Friendships` — `keepAlive`, `@JsonPersist()`, `persist()`, static `Mutation` fields; `FriendStatus` enum; `friendStatusProvider`; invalidated by `AppStartup` on `/social` notification taps |
| `lib/features/social/presentation/widgets/friend_actions.dart` | `FriendActions` — routes on `FriendStatus`, compact/full layout variants |
| `lib/features/social/presentation/widgets/friend_buttons.dart` | `SendRequestButton`, `AcceptButton`, `RemoveFriendButton`, `DeclineRequestButton` — own their mutation state via `Friendships.{send,accept,remove}` |
| `lib/shared/providers/player_providers.dart` | `PlayerInfoCache` — `keepAlive`, `@JsonPersist()`; key auto-generated from family `id` arg |
| `lib/features/auth/providers/auth_providers.dart` | `AuthController.signOut` / `deleteAccount` — call `deleteUserData` |
| `lib/core/startup/app_startup.dart` | Pre-warm `currentUserProfileProvider` in `_onAuthStateChange`; invalidate `friendshipsProvider` on `/social` notification taps |

### Dependencies

```yaml
dependencies:
  riverpod_sqflite: ^0.4.2   # JsonSqFliteStorage backend
  sqflite: ^2.4.2             # SQLite engine
  path: ^1.9.1                # getDatabasesPath join
```

`riverpod_sqflite` provides `JsonSqFliteStorage`. `sqflite` and `path` are direct dependencies because `storage_provider.dart` imports them directly (`depend_on_referenced_packages` lint).

---

## 24. Backward Compatibility — evolving the game without breaking shipped apps

This is the companion to [`versioning.md`](versioning.md). That doc covers the
**engine Dart API** and **engine SQL** contracts (semver, expand/contract, the
release/rollout flow). This section covers what bites once a *game* is in real
users' hands and you want to change a rule or add a feature: the **game JSONB
payloads** (config / state / observation / action), the **client caches**, and
the **client↔server version negotiation** that bounds how long old clients must
be supported.

The guiding fact: once an app ships, client and server **no longer move
together**. Mobile update lag means a `v(n)` binary keeps calling a newer backend
for weeks, and a `Daily`-timed game can outlive several app releases. Every change
must answer: *"what does an old client, and an in-flight game started under the
old rules, do when they meet the new code?"*

### Three version axes (keep independent)

| Axis | Granularity | Where it lives | Who reads it |
|------|-------------|----------------|--------------|
| **Engine semver** | per engine release | git tag `vX.Y.Z`, `pubspec.yaml` | build/release |
| **Game schema version** | per game *type* revision | `games.schema_version` column (threaded to the SQL hooks as `p_schema_version`; on `Game`/`BaseEngine` client-side) | `game_apply_action` (SQL) + `BaseEngine.parseObservation` (Dart) |
| **Cache schema version** | per persisted model | each provider's `destroyKey` | `riverpod_sqflite` on cold start |

An engine release may touch none, one, or several of these.

### The five compatibility surfaces

| # | Surface | Breaks when | Mechanism |
|---|---------|-------------|-----------|
| 1 | **Engine Dart API** (barrel, `runEngineApp`, `GameModule`/`BaseEngine`) | compile time | engine semver — [`versioning.md`](versioning.md) |
| 2 | **Engine SQL** (infra migrations + the app-owned hooks) | runtime, vs live DBs + installed binaries | expand/contract — [`versioning.md`](versioning.md) |
| 3 | **Game JSONB** (`games.config`, `game_states.state`, `observations.data`, action `p_data`) | in-flight games | **game schema version** (below) |
| 4 | **Client caches** (`riverpod.db`, SharedPreferences, image cache) | cold-start decode of stale rows | **`destroyKey` discipline + tolerant decode** (below) |
| 5 | **Client↔server version** | old client meets new backend | **client-version header + `min_supported_version` gate** (designed; **deferred** — Android uses Play in-app-update) |

**Authority note.** The client `BaseEngine.isValidAction` is **UX-only** (it greys
out illegal taps); the authoritative rule check is the server hook
`game_apply_action`. This is what lets many rule changes ship **server-side
only** (see the decision checklist).

### Surface 3 — game schema version (version the game *type*)

A breaking rules/schema change does **not** mutate existing games in place.
Instead each game is **stamped with the schema version it was created under**, and
that version is honored for the game's whole life.

**Where it lives.** A first-class **`games.schema_version` column**
(`INT NOT NULL DEFAULT 1`) — set once at creation (from the client's
`GameModule.schemaVersion`, written by `create_game`) and immutable. It is kept
**out of** the opaque `config`/`state`/observation JSONB so those payloads stay
game-owned and the drain query is a plain column scan. The engine threads it to
all game SQL hooks as an explicit `p_schema_version` parameter, and surfaces it on
the `Game` model (`required int schemaVersion` — the `NOT NULL` column always
provides it) and on `BaseEngine.schemaVersion`.

**Client gating.** `gameEngineProvider` reads the game's `schemaVersion` and calls
`GameModule.supportsSchema(version)` (`version <= schemaVersion`). A game created
by a *newer* build raises `UnsupportedGameSchemaException` rather than mis-parsing
with old code; otherwise it builds the engine stamped at the game's version.

**How both sides branch.**

```sql
-- server: game_apply_action(..., p_config, p_schema_version)
CASE p_schema_version
  WHEN 1 THEN /* original rules (kept until v1 games drain) */
  WHEN 2 THEN /* new rules */
END
```

```dart
// client: BaseEngine.parseObservation, branching on this.schemaVersion
ObservationData parseObservation(Map<String, dynamic> json) =>
    switch (schemaVersion) {
      1 => ObservationDataV1.fromJson(json),
      _ => ObservationData.fromJson(json),
    };
```

**Retiring an old version — two paths, two lifetimes.** Old code splits in two:

- **Write path** (`game_apply_action`, `game_handle_system_action` — anything that
  *advances* state) can be retired once **both**: (1) the **drain query** returns
  zero — `SELECT count(*) FROM games WHERE status='active' AND schema_version < N;`
  — and (2) the **force-update floor** has passed the last app version that could
  *create* that schema. Active games are the only callers of the write path, so
  once they drain it is dead.
- **Read / projection / render path** (`game_compute_observation` on the server,
  `BaseEngine.parseObservation` + rendering on the client) must survive **as long
  as you want to replay games created under that schema** — *not* bounded by
  draining. `get_replay` re-projects every historical `game_states` row through
  `game_compute_observation` at the game's own `schema_version`, so replays of an
  old finished game stay requestable long after the last active old-schema game
  ended. Retire this path only when you drop replay support for that schema.

In short: **draining gates the write path; replay gates the read path, and replay
outlives draining.** Additive, non-breaking changes do **not** bump the schema —
Surface 3b's decode tolerance absorbs them.

### Surface 3b — decode-tolerance rules (the load-bearing client convention)

Within a single schema version, evolution must be **forward- and
backward-tolerant**: an old client may receive new-shaped JSON, and a new client
may read old-shaped JSON (and old cached rows).

- **New fields must be nullable or `@Default(...)`.** Never add a `required` field
  within an existing schema version.
- **Enums must use `@JsonKey(unknownEnumValue: …)`** (or a sentinel) so an unknown
  value degrades gracefully instead of throwing. Applies to engine models too
  (`GameStatus`, `GameAccess`, `OutcomeResult`, `RelationshipStatus`,
  `ParticipantType` already carry an `unknown` sentinel).
- **Changing a field's type or meaning, or removing it, is breaking** → bump the
  game schema version; do not edit in place.
- These rules apply **identically** to server-response models *and* `@JsonPersist`
  cached models, because cached rows are re-decoded through the same `fromJson` on
  cold start.

### Surface 4 — client caches

On-device state lives in three places: **`riverpod.db`** (the three `@JsonPersist`
providers — `CurrentUserProfile`, `Friendships`, `PlayerInfoCache`; see §23),
**SharedPreferences** (`theme_mode`, `total_wins`, …), and the
**`cached_network_image`** disk cache (avatars bust with `?v=timestamp`).
Discipline:

- **`destroyKey` == the persisted model's schema version, per provider.** Bump the
  *individual* provider's `destroyKey` when its model's persisted shape changes
  breakingly — do not share one global key, so a profile change does not wipe the
  friendships cache.
- **A cached-row decode failure must be a cache miss** (drop the row, re-fetch),
  never a crash — the safety net when an old row predates a schema bump.
- **SharedPreferences reads must default safely.** If a key's value shape ever
  changes, write under a new key rather than reinterpreting the old one.
- **`deleteUserData` deliberately does not clear `PlayerInfoCache`** — player
  identity is public and survives sign-out by design; the per-provider `destroyKey`
  is its only invalidation lever.

### Surface 5 — client↔server version negotiation (DESIGN ONLY — deferred)

> **Not built.** While Android-only, Play in-app-update handles forced updates (see
> Implementation status #4). This is the blueprint for when the gate is
> reintroduced (iOS/web, or backend-authoritative contraction).

To *contract* old shapes you must know which client versions are still live and be
able to force the floor up. The design: send `X-Client-Version` (+ platform) as a
global PostgREST header at init; add `min_supported_version` / `soft_min_version`
(per platform) to `private.app_config`, exposed via a `SECURITY DEFINER`
`get_client_requirements(p_platform)` RPC; at startup, block below the hard floor
(Android drives `UpdateNotifier`; iOS/web show a store link / reload) and nudge
between soft and hard. Keeping the gate platform-agnostic means iOS/web reuse it
unchanged. The floor is what bounds the support window in Surfaces 2–4: once it
passes the last app version that knew an old SQL shape or game schema, you may
*contract*.

### Deploy playbook (expand → ship → contract)

Same as [`versioning.md`](versioning.md), applied to game changes:

1. **Expand** — ship the additive DB change (new column / `_v2` RPC / new schema
   branch in the hooks) **before or with** the app release; old shapes keep working.
2. **Ship** — the new app creates games at the new schema; old apps keep
   creating/reading the old one against the same DB.
3. **Contract** — retire old code per the two-path rule: the **write path** once
   the drain query is zero **and** the force-update floor has retired old apps; the
   **read/projection/render path** only when you stop supporting replay for that
   schema.

Per-app: vendor with `dart run eigen_engine:sync_supabase`, apply per Supabase
project; migrations are append-only/forward-only (fix forward, never roll back).

### Quick checklist — "I want to change the game"

- Alters the **observation/action/config shape**, or makes in-flight games
  inconsistent/unfair? → **breaking**: bump `GameModule.schemaVersion`
  (→ `games.schema_version`), add new server + client branches, drain old games,
  raise the force-update floor before contracting.
- Purely additive (new optional field/feature)? → nullable / `@Default`, **no bump**;
  old clients ignore it, new clients default it.
- Server-only rule logic, same shapes, in-flight games stay consistent? → change
  `game_apply_action` only, **no bump**.
- New enum value? → ensure `unknownEnumValue` tolerance is already shipped, then
  expand/contract.
- Touching a persisted model's shape? → bump **that provider's** `destroyKey`.

### Implementation status (built)

Three of the four foundations are implemented (dev-phase, in-place); the version
gate (Surface 5) is **designed but deliberately not built**.

1. **Game schema version** — `games.schema_version` column; `create_game` stores it
   from `GameModule.schemaVersion`; threaded to all game hooks as `p_schema_version`;
   surfaced on `Game`/`BaseEngine.schemaVersion` and gated by
   `GameModule.supportsSchema` in `gameEngineProvider` (render path). **Join is
   gated too:** `join_game`/`join_game_by_code` take the client's max supported
   schema and refuse to seat the caller in a newer-schema game, so every join path
   (lobby, friends, by-code, deep link) is blocked *before* a participant row is
   created — not only when the game screen later tries to render. The lobby also
   disables the Join button for unsupported games as immediate feedback.
2. **Decode tolerance** — `unknown` sentinel + `@JsonKey(unknownEnumValue:)` on the
   wire enums (`GameStatus`, `GameAccess`, `OutcomeResult`, `RelationshipStatus`,
   `ParticipantType`). Guarded by `test/core/decode_tolerance_test.dart`.
3. **Cache discipline** — each `@JsonPersist` provider documents its per-provider
   `destroyKey` bump rule; decode-failure is a safe cache-miss (riverpod core);
   `PlayerInfoCache` intentionally survives sign-out.
4. **Version gate (Surface 5) — DEFERRED.** While Android-only, forced updates are
   handled by Play in-app-update (immediate priority) via the existing
   `UpdateNotifier`, so a server-side gate would guard nothing yet. **Re-introduce
   when any of:** (a) iOS or web ships (no Play in-app-update equivalent); (b) you
   need backend-authoritative "who's live?" before a risky contraction; (c) you want
   telemetry of live client versions. Until then, the force-update floor on Android
   is Play-driven, not a server gate — "is it safe to contract?" is judged from Play
   Console adoption rather than backend telemetry.
