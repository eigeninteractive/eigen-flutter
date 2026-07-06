# Eigen Engine

A Flutter + Supabase **whitelabel engine** for turn-based multiplayer games
(auth, realtime, timing, ratings, social, notifications). A game plugs in as a
single Dart `GameModule` plus a handful of SQL hooks; an app boots with
`runEngineApp(...)`.

This is a **standalone package** with no bundled example game. An app depends on
it and supplies a `GameModule`. Until the engine is published to pub.dev, clone
it as a **sibling** of your app and depend on it by **path**:

```yaml
# in your app's pubspec.yaml
dependencies:
   eigen_engine:
      path: ../eigen_engine
```

The engine's generated code (`*.g.dart`, `*.freezed.dart`) is **not committed**,
so after cloning, generate it once — and again in CI before building the app:

```bash
cd eigen_engine && flutter pub get && dart run build_runner build
```

See [`docs/game_implementation_guide.md`](docs/game_implementation_guide.md).
[`seenu-k/strategy`](https://github.com/seenu-k/strategy) is the reference app
built on this engine.

## Layout

```
eigen_engine/
├── lib/
│   ├── eigen_engine.dart   # Public barrel (runEngineApp, AppConfig, GameModule, …)
│   ├── app_runner.dart     # runEngineApp(...) entry point + root MyApp
│   ├── core/               # config, game contract, navigation, notifications, theme, storage, …
│   ├── features/           # auth, game, home, profile, rating, settings, social
│   └── shared/             # shared widgets
├── bin/
│   └── sync_supabase.dart # CLI: vendors the engine backend into an app
├── supabase/                # the engine backend (canonical):
│   ├── migrations/          #   framework/infra schema + RPCs
│   ├── functions/           #   the single `game` edge function (engine harness +
│   │                        #   _engine framework + example game.ts)
│   ├── seed.sql             #   engine app_config + serverless-secret seed
│   └── config.toml          #   reference config (apps base theirs on it)
└── docs/                    # engine_architecture.md, game_implementation_guide.md
```

## Using the engine in an app

1. Add the `eigen_engine` dependency (above) to your app.
2. Implement a `GameModule` (rules engine + content widget + models) under
   `lib/game/`; register it in `main.dart` via
   `runEngineApp(module: const MyGameModule(), config: AppConfig(…), …)`.
3. Vendor the engine backend (migrations + functions + seed) into your committed
   `supabase/`: `dart run eigen_engine:sync_supabase`.
4. Implement your game's rules. All six hooks are
   **TypeScript** in the vendored `engine` edge function — you edit only
   `supabase/functions/_lib/game.ts` (the sync scaffolds it once; everything
   else in that function is engine-owned). Add a `[functions.engine]` block to
   your `config.toml` (it is per-app, not vendored).

The full walkthrough — project structure, the `GameModule` contract, the SQL
hooks, timing, ratings, deep links — is in
[`docs/game_implementation_guide.md`](docs/game_implementation_guide.md).
[`docs/engine_architecture.md`](docs/engine_architecture.md) explains how the
engine works internally; the [Versioning & backward
compatibility](#versioning--backward-compatibility) section below covers how the
engine and apps evolve in production.

## Development

```bash
dart pub get
dart run build_runner build
flutter analyze

# Edge functions (TypeScript) — same checks CI runs:
deno fmt --check supabase/functions
deno lint supabase/functions
```

## Versioning & backward compatibility

How the engine and the apps built on it evolve once both are in production with
real users. The engine and each app are **separate, long-lived repos**, and
every app runs its **own Supabase project**. Three contracts can break across
versions, each at a different layer:

1. **Engine Dart API** — the `eigen_engine.dart` barrel, `runEngineApp`, the
   config/module/engine types, and exported providers. Breaks at **compile
   time**.
2. **Engine SQL** — the infra schema, RPCs, and triggers in
   `supabase/migrations/`. Breaks at **runtime**, against live databases *and*
   app binaries already installed on users' devices.
3. **Game state / observation JSONB** — the per-game payload. Breaks
   **in-flight games**.

For the deep-dive on contract 3 — client caches and the client↔server version
gate that bounds how long old clients must be supported — see
[`docs/engine_architecture.md`](docs/engine_architecture.md) §24 (Backward
Compatibility). This section is the high-level policy.

### Versioning scheme (semver, via `cider`)

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

### How an app depends on the engine

**Until the engine is published to pub.dev**, an app depends on it by **path**,
cloned as a sibling (see the top of this README) — the same in local and CI.

- **Generated code is not committed** (`*.g.dart`, `*.freezed.dart` are
  git-ignored), so after cloning the engine you must run `dart run
  build_runner build` in it before the app can analyze/build. CI does the same
  (checkout engine as a sibling → generate its code → build the app).
- **Commit `pubspec.lock`.** With a path dependency the lock records the engine
  as `path`, consistent between local and CI (both resolve the same sibling), so
  it commits cleanly and pins the pub.dev deps.

**Future (pub.dev):** once published, apps switch to a hosted dependency
(`eigen_engine: ^X.Y.Z`) with generated code shipped in the archive — at which
point the semver rules above become the contract.

### SQL + live users — the hard part (expand / contract)

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
- **Use expand/contract (parallel change):** (1) **expand** — add the new column
  / new RPC (or a `_v2` RPC) *additively*, leaving the old one working; (2)
  **ship** — the new app uses the new shape, old apps keep using the old shape
  against the same DB; (3) **contract** — drop the old shape *only after* old app
  versions are retired.
- **Forced-update floor.** Maintain a minimum-supported-app-version gate (the
  engine already integrates `in_app_update` on Android and knows the running
  version): below the floor the app blocks until updated. This bounds how long
  the DB must serve old clients, so you can *contract* sooner.
- **Deploy order.** The DB *expand* migration ships **before or with** the app
  version that needs it — never an app version that requires a column or RPC the
  production DB does not yet have.

### Game state / observation JSONB (in-flight games)

Game state is opaque JSONB, and games can be long-running — a `Daily`-timed game
can span days and survive an app/engine upgrade mid-game. Therefore:

- `ObservationData` / state `fromJson` must **tolerate older shapes** — default
  any newly added fields so a game created under `vN` still parses under `vN+1`.
- For larger changes, **version the game type** (the `games.schema_version`
  column, threaded to the hooks as `p_schema_version` and surfaced on
  `Game`/`BaseEngine`) and branch on it on both server and client. See
  [`docs/engine_architecture.md`](docs/engine_architecture.md) §24 for the full
  scheme, including the drain-query + force-update-floor retirement gate.
- `game_states` is append-only, so an in-flight game's earlier rows were written
  under the old shape; the `apply_action` hook must handle every shape a
  still-running game could have been started under, until those games finish.

### Per-app rollout (N apps, N Supabase projects)

An engine SQL change must be **vendored** into each app (`dart run
eigen_engine:sync_supabase`) and applied to each app's Supabase project.
Sequence per project: apply the *expand* migration, then ship the app update.
Production migrations are forward-only, so prefer **additive** changes (a bad app
release is then fixed by shipping a new app version, with no database rollback),
and if a migration itself is wrong, ship a **compensating forward migration**
rather than rolling back.

### Checklists

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
- *Contract* the old DB shape in a later release once old app versions retire.

### Tooling — `cider`

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

## Running the engine backend locally

The local Supabase stack needs two git-ignored files that aren't committed (a
JWT signing key and edge-function secrets). After a fresh clone, create them
once, then start the stack (requires Docker):

```bash
./bin/setup_local.sh          # creates supabase/signing_keys.json + functions/.env.local
supabase start                # applies migrations, boots Postgres/Auth/Realtime
supabase functions serve      # optional: run the edge functions locally
```

`setup_local.sh` is idempotent — it won't clobber existing files. The signing
key is a JWK array (config.toml's `[auth] signing_keys_path`); without it
`supabase start` fails.

The edge-function TypeScript derives its DB enums from
`supabase/functions/_types/database.types.ts`, which is **generated from the
engine schema**. Regenerate it whenever you change a migration (the committed
file ships as an enums-only baseline until first generated):

```bash
supabase start && ./bin/generate_db_types.sh   # writes _types/database.types.ts from the local DB
```

CI regenerates the same file and fails on any diff, so migrations and types
can't drift — commit the regenerated file alongside the migration change.
