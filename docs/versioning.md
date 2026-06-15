# Versioning & Backward Compatibility

How **Eigen Engine** and the apps built on it evolve once both are in production
with real users.

## Why this matters

Eigen Engine and each app are **separate, long-lived repos**, and every app runs
its **own Supabase project** with real users on installed (mobile) binaries.
Three contracts can break across versions, each at a different layer:

1. **Engine Dart API** — the `eigen_engine.dart` barrel plus `runEngineApp`,
   `AppConfig`/`EngineConfig`/`Branding`, `GameModule`/`BaseEngine`/
   `GameContentContext`, and the exported providers. Breaks at **compile time**.
2. **Engine SQL** — the infra schema, RPCs, and triggers in
   `supabase/migrations/`. Breaks at **runtime**, against live databases *and*
   app binaries already installed on users' devices.
3. **Game state / observation JSONB** — the per-game payload. Breaks
   **in-flight games**.

## Versioning scheme (semver, via `cider`)

The engine's **public API = the Dart barrel + the SQL migration set**.

- **0.y.z (current).** API is still evolving — breaking changes may land in a
  **MINOR** bump. Stay here until the API has proven itself across a couple of
  real games.
- **≥ 1.0.0.** **MAJOR** = a breaking Dart API change *or* a breaking SQL
  contract change; **MINOR** = additive (new API, additive migrations);
  **PATCH** = fixes.

Each **app** carries its own, independent semver and records the engine version
it was built against (in its CHANGELOG). Engine releases are **git tags**
`vX.Y.Z`.

## How an app depends on the engine

**Until the engine is published to pub.dev**, an app depends on it by **path**,
cloned as a sibling — the same in local and CI:

```yaml
dependencies:
  eigen_engine:
    path: ../eigen_engine
```

- **Generated code is not committed in the engine** (`*.g.dart`,
  `*.freezed.dart` are git-ignored), so after cloning the engine you must run
  `dart run build_runner build` in it before the app can analyze/build. CI does
  the same (checkout engine as a sibling → generate its code → build the app).
- **Private engine in CI:** check out the engine with `actions/checkout`
  (`repository: seenu-k/eigen_engine`, `ssh-key: ${{ secrets.ENGINE_DEPLOY_KEY }}`)
  beside the app, then generate + build.
- **Commit `pubspec.lock`.** With a path dependency the lock records the engine
  as `path`, which is consistent between local and CI (both resolve the same
  sibling), so it commits cleanly and pins the pub.dev deps.

**Future (pub.dev):** once the engine is published, apps switch to a hosted
dependency (`eigen_engine: ^X.Y.Z`) with the generated code shipped in the
published archive — at which point the semver rules below become the contract,
and git-tag pinning is an option for reproducible builds.

## SQL + live users — the hard part (expand / contract)

Once an app's Supabase project is **in production**:

- **Migrations are append-only and forward-only.** Never edit a migration that
  has been applied to a production database; ship every change as a new,
  later-timestamped migration. (The early-dev habit of editing migrations in
  place ends at the first production deploy.)
- **Mobile update lag is the core constraint.** After you ship app `v(n+1)`,
  users on `v(n)` keep calling the *same production database* with old
  expectations for days or weeks. So every **client-visible** DB change (an RPC
  signature or behaviour, or a table shape clients read over realtime) must stay
  **backward-compatible with every app version still in the wild**.
- **Use expand/contract (parallel change):**
  1. **Expand** — add the new column / new RPC (or a `_v2` RPC) *additively*;
     leave the old one working.
  2. **Ship** — the new app version uses the new shape; old app versions keep
     using the old shape against the same DB.
  3. **Contract** — drop the old shape *only after* old app versions are retired.
- **Forced-update floor.** Maintain a minimum-supported-app-version gate (the
  engine already integrates `in_app_update` on Android and knows the running
  version): below the floor the app blocks until updated. This bounds how long
  the DB must serve old clients, so you can *contract* sooner.
- **Deploy order.** The DB *expand* migration ships **before or with** the app
  version that needs it — never an app version that requires a column or RPC the
  production DB does not yet have.

## Game state / observation JSONB (in-flight games)

Game state is opaque JSONB, and games can be long-running — a `Daily`-timed game
can span days and survive an app/engine upgrade mid-game. Therefore:

- `ObservationData` / state `fromJson` must **tolerate older shapes** — default
  any newly added fields so a game created under `vN` still parses under `vN+1`.
- For larger changes, **version the state** (a `v` / `schema` field) and branch
  on it.
- `game_states` is append-only, so an in-flight game's earlier rows were written
  under the old shape; the `apply_action` hook must handle every shape a still-
  running game could have been started under, until those games finish.

## Per-app rollout (N apps, N Supabase projects)

An engine SQL change must be **vendored** into each app
(`dart run eigen_engine:sync_supabase`) and applied to each app's Supabase
project. Sequence per project: apply the *expand* migration, then ship the app
update. Production migrations are forward-only, so:

- Prefer **additive** changes — a bad app release is then fixed by shipping a new
  app version, with no database rollback.
- If a migration itself is wrong, ship a **compensating forward migration**
  rather than trying to roll back.

## Checklists

**Engine change**
- Dart API changed? → bump semver, note it in `CHANGELOG.md`.
- SQL changed? → make it additive; apply expand/contract; ask "does this break a
  client version still in the wild?" If yes, keep the old path until the
  forced-update floor passes.
- `cider bump` → commit → `git tag vX.Y.Z` → `git push --tags`.

**App release**
- Pin the engine tag (git dep); re-vendor migrations.
- Apply the *expand* migration to the production DB **first**.
- Ship the app; record the engine version in the app CHANGELOG.
- *Contract* the old DB shape in a later release once the old app versions are
  retired.

## Tooling — `cider`

The engine is versioned with [`cider`](https://pub.dev/packages/cider)
(`CHANGELOG.md` + `pubspec.yaml`):

```bash
dart pub global activate cider          # once
# as you work, in eigen_engine/:
cider log added   "…"
cider log changed "…"
cider log fixed   "…"
# cut a release:
cider bump minor                        # or patch; major only once ≥ 1.0
git commit -am "chore: release $(cider version)"
git tag "v$(cider version)" && git push --tags
```
