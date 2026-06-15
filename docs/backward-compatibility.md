# Backward Compatibility — evolving rules & features without breaking shipped apps

This is the deep-dive companion to [`versioning.md`](versioning.md). That doc
covers the **engine Dart API** and **engine SQL** contracts (semver,
expand/contract, the release/rollout flow). This one covers the parts that bite
once a *game* is in real users' hands and you want to change a rule or add a
feature:

- the **game JSONB payloads** (config / state / observation / action),
- the **client caches**, and
- the **client↔server version negotiation** that bounds how long old clients
  must be supported.

The guiding fact: once an app ships, the client and server **no longer move
together**. Mobile update lag means a `v(n)` binary keeps calling a newer
backend for weeks, and a `Daily`-timed game can outlive several app releases. So
every change has to answer: *"what does an old client, and an in-flight game
started under the old rules, do when they meet the new code?"*

## What exists today (the starting point)

- The only "version" in the system is the **per-game optimistic-lock counter**
  `game_states.version` (mirrored to `observations.version`, passed back as
  `p_expected_version`; mismatch raises `Stale state` — see
  `error_messages.dart`). It is **not** a rules/schema version.
- `games.config`, `game_states.state`, `observations.data`, and action payloads
  are **opaque, untagged JSONB**. There is no schema/rules version anywhere.
- The app version (`strategy` `1.3.0`) is **display-only** — never sent to the
  backend. There is **no `min_supported_version` gate**. Update enforcement is
  **Android-only** Play in-app-update (`lib/core/updates/update_notifier.dart`);
  iOS/web have none. `private.app_config` is not REST-exposed.
- JSON decode (freezed + json_serializable, `field_rename: snake`) **tolerates
  added fields** but **throws** on a missing `required` field or an unknown enum
  value. There is currently **no `@Default` and no `unknownEnumValue`** in the
  codebase.
- Client caches use a single shared `destroyKey: '1'` across all three
  `@JsonPersist` providers.

Most of the mechanisms below are therefore **conventions + a small amount of new
plumbing**, enumerated as follow-ups at the end. This document is the
architecture they implement against.

## The five compatibility surfaces

| # | Surface | Breaks when | Mechanism |
|---|---------|-------------|-----------|
| 1 | **Engine Dart API** (barrel, `runEngineApp`, `GameModule`/`BaseEngine`) | compile time | engine semver — [`versioning.md`](versioning.md) |
| 2 | **Engine SQL** (infra migrations + the 4 app-owned hooks) | runtime, vs live DBs + installed binaries | expand/contract — [`versioning.md`](versioning.md) |
| 3 | **Game JSONB** (`games.config`, `game_states.state`, `observations.data`, action `p_data`) | in-flight games | **game schema version** (below) |
| 4 | **Client caches** (`riverpod.db`, SharedPreferences, image cache) | cold-start decode of stale rows | **`destroyKey` discipline + tolerant decode** (below) |
| 5 | **Client↔server version** | old client meets new backend | **client-version header + `min_supported_version` gate** (below) |

Authority note: the client `BaseEngine.isValidAction` is **UX-only** (it greys
out illegal taps); the authoritative rule check is the server hook
`private.game_apply_action`. This is what lets many rule changes ship
**server-side only** — see the decision trees.

## Three version axes

| Axis | Granularity | Where it lives | Who reads it |
|------|-------------|----------------|--------------|
| **Engine semver** | per engine release | git tag `vX.Y.Z`, `pubspec.yaml` | build/release |
| **Game schema version** | per game *type* revision | `games.config.schema` (mirrored into `game_states.state.schema`) | `game_apply_action` (SQL) + the engine's `parseObservation` (Dart) |
| **Cache schema version** | per persisted model | each provider's `destroyKey` | `riverpod_sqflite` on cold start |

Keep these independent. An engine release may touch none, one, or several of the
other two.

## Surface 3 — game schema version (the core idea: version the game *type*)

A breaking rules/schema change does **not** mutate existing games in place.
Instead each game is **stamped with the schema version it was created under**,
and that version is honored for the game's whole life.

**Where it lives.** A `schema` integer in **`games.config`** — set once at
creation and immutable. `games.config` already flows to the engine
(`module.createEngine(game.config)`) and is readable by every SQL hook, so it is
the natural home. Mirror it into each `game_states.state` (the hooks already own
state shape) so a state row is **self-describing** even without the config row.

```jsonc
// games.config
{ "schema": 2, /* game-specific config… */ }

// game_states.state (mirrored)
{ "schema": 2, "board": [...], "action_count": 7 }
```

**How both sides branch.**

```sql
-- server: private.game_apply_action(state, pending, action, player_index, seed, config)
CASE (state->>'schema')::int
  WHEN 1 THEN /* original rules (kept until v1 games drain) */
  WHEN 2 THEN /* new rules */
END
```

```dart
// client: BaseEngine.parseObservation / engine logic
ObservationData parseObservation(Map<String, dynamic> json) =>
    switch (json['schema'] as int? ?? 1) {
      1 => ObservationDataV1.fromJson(json),
      _ => ObservationData.fromJson(json),
    };
```

**Creation always stamps the current version.** `GameModule.creationSpec`'s
`defaultConfig` seeds it on the client; `private.game_initial_state` writes it
into the first state row on the server. New games are always created at the
latest schema.

**Retiring an old version.** An old code path is removed only after **both**:
1. the **drain query** returns zero —
   `SELECT count(*) FROM games WHERE status='active' AND (config->>'schema')::int < N;`
   (no active game still runs the old schema), **and**
2. the **force-update floor** (surface 5) has passed the last app version that
   could create or render that schema.

Until then, the old `CASE`/`switch` branch stays. Additive, non-breaking changes
do **not** bump `schema` — surface 4's decode tolerance absorbs them.

## Surface 3b — decode-tolerance rules (the load-bearing client convention)

Within a single schema version, evolution must be **forward- and
backward-tolerant**, because an old client may receive new-shaped JSON and a new
client may read old-shaped JSON (and old cached rows). Rules:

- **New fields must be nullable or `@Default(...)`.** Never add a `required`
  field within an existing schema version.
- **Enums must use `@JsonKey(unknownEnumValue: …)`** (or a sentinel), so an
  unknown value degrades gracefully instead of throwing. This applies to engine
  models too (e.g. a future `GameStatus`/`GameAccess` value).
- **Changing a field's type or meaning, or removing it, is a breaking change** →
  bump the game `schema` (new type revision); do not edit in place.
- These rules apply **identically** to server-response models *and*
  `@JsonPersist` cached models, because cached rows are re-decoded through the
  same `fromJson` on cold start.

> **Current gap:** there is not a single `@Default` or `unknownEnumValue` in the
> codebase, so today a missing field or new enum value throws. Retrofitting these
> is follow-up #2.

## Surface 4 — client caches

On-device state lives in three places:

1. **`riverpod.db`** (sqflite via `JsonSqFliteStorage`,
   `lib/core/storage/storage_provider.dart`) backing the three `@JsonPersist`
   providers: `CurrentUserProfile` (`profileCacheKey`), `Friendships`
   (`friendshipsCacheKey`), `PlayerInfoCache` (family key by id). All currently
   `StorageCacheTime.unsafe_forever` + `destroyKey: '1'`.
2. **SharedPreferences** keys: `theme_mode`, `total_wins`,
   `notifications_permission_requested`.
3. **`cached_network_image`** disk cache (avatars use `?v=timestamp` busting).

Discipline:

- **`destroyKey` == the persisted model's schema version, per provider.** Bump
  the *individual* provider's `destroyKey` whenever its model's persisted shape
  changes breakingly. Stop sharing one global `'1'` — a profile change should not
  wipe the friendships cache.
- **A cached-row decode failure must be treated as a cache miss** (drop the row,
  re-fetch), never a crash. This is the safety net when an old row predates a
  schema bump; document/enforce it at the `persist(...)` boundary.
- **SharedPreferences reads must default safely** (today `theme_mode`/`total_wins`
  already do). If a key's value shape ever changes, write under a new key rather
  than reinterpreting the old one.
- **`deleteUserData` gap:** it clears profile + friendships but **not**
  `PlayerInfoCache`; sign-out leaves stale player identities. Fix in follow-up #3.

## Surface 5 — client↔server version negotiation (Android now, iOS/web-ready)

To *contract* old shapes you must know which client versions are still live and
be able to force the floor up. Today the backend knows neither.

**Client → server.** Send `X-Client-Version` (and platform) on Supabase calls —
a global PostgREST header set at init, sourced from `packageInfoProvider`. This
makes every request self-identifying for telemetry and gating.

**The gate.** Add `min_supported_version` and `soft_min_version` (per platform)
to `private.app_config`. Because `app_config` is private (not REST-exposed),
expose them through a tiny `SECURITY DEFINER` RPC, e.g.
`get_client_requirements(p_platform text)`.

**Enforcement (startup).**
- Below the **hard** floor → blocking "update required" screen. Android drives
  `UpdateNotifier`'s immediate update; iOS/web show a store link / reload (stubs
  for now).
- Between **soft** and **hard** → a non-blocking "update available" nudge.

Designing the gate **platform-agnostic** (a version + platform → requirement
lookup) means iOS and web (P1) reuse it unchanged; only the per-platform
"how to update" action differs.

The floor is what bounds the support window in surfaces 2–4: once it passes the
last app version that knew an old SQL shape or game schema, you may *contract*.

## Deploy playbook (expand → ship → contract)

Unchanged from [`versioning.md`](versioning.md), applied here to game changes:

1. **Expand** — ship the additive DB change (new column / `_v2` RPC / new
   `schema` branch in the hooks) **before or with** the app release; old shapes
   keep working.
2. **Ship** — the new app creates games at the new `schema`; old apps keep
   creating/reading the old one against the same DB.
3. **Contract** — remove the old `schema` branch / column only after the drain
   query is zero **and** the force-update floor has retired the old apps.

Per-app: vendor with `dart run eigen_engine:sync_supabase`, apply per Supabase
project; migrations are append-only/forward-only (fix forward, never roll back).

## Worked decision trees

**1. Tweak a rule, schema unchanged** (e.g. adjust a win condition).
Server-authoritative: change `game_apply_action` only; clients tolerate (their
`isValidAction` is advisory). **No `schema` bump** — *unless* the change would
make games already in progress inconsistent or unfair, in which case treat it as
breaking (bump `schema`, new games only).

**2. Add an optional feature / field** (e.g. an optional config toggle, an extra
observation field). Additive: make it nullable or `@Default`. No `schema` bump;
old clients ignore it, new clients default it.

**3. Add an enum value** (e.g. a new `GameStatus`). Requires
`@JsonKey(unknownEnumValue: …)` already in place so old clients don't crash;
roll out via expand/contract.

**4. Breaking schema change** (e.g. board shape changes, action format changes).
Bump `games.config.schema`; add the new branch to the hooks and the engine; new
games use it; existing games finish on their old branch; remove the old branch
after drain + floor.

## Follow-up implementation tasks (not built yet)

This doc is the design; these are the changes it implies, each to be planned and
**tested** separately:

1. **Game schema version** — `schema` in `games.config` + the module
   `defaultConfig`/`game_initial_state` stamping; `CASE`/`switch` scaffolding in
   `game_apply_action` and `BaseEngine.parseObservation`.
2. **Decode tolerance** — retrofit `@Default` / `@JsonKey(unknownEnumValue:)`
   across shipped + persisted models; add an analyzer or test guard so new
   models can't regress it.
3. **Cache discipline** — per-provider `destroyKey` convention, decode-failure =
   cache-miss fallback, and `deleteUserData` also clearing `PlayerInfoCache`.
4. **Version gate** — `X-Client-Version` header, `min_supported_version` /
   `soft_min_version` in `app_config`, the `get_client_requirements` RPC, and
   startup enforcement (Android wired to `UpdateNotifier`; iOS/web stubs).

## Quick checklist — "I want to change the game"

- Does the change alter the **observation/action/config shape**, or make
  in-flight games inconsistent? → **breaking**: bump `games.config.schema`, add
  new server + client branches, drain old games, raise the force-update floor
  before contracting.
- Purely additive (new optional field/feature)? → nullable/`@Default`, **no
  bump**.
- Server-only rule logic, same shapes, in-flight games stay consistent? → change
  `game_apply_action` only, **no bump**.
- New enum value? → ensure `unknownEnumValue` tolerance, expand/contract.
- Touching a persisted model's shape? → bump **that provider's** `destroyKey`.
