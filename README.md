# Eigen Flutter

The **client half** of the Eigen engine — a whitelabel Flutter package for
turn-based multiplayer games (auth, the game socket, timing, ratings, social,
notifications, the whole app shell). A game plugs in as a single Dart
`GameModule`; an app boots with `runEngineApp(...)`.

The **server half** lives in the sibling [`eigen-server`](https://github.com/eigeninteractive/eigen-server)
repo — a Cloudflare Worker (Durable Objects + D1). This package talks to it over
a generated REST client plus one WebSocket per game.

## The example is the documentation

[`example/`](example/) is a complete game — Rock–Paper–Scissors, in about 500
lines — and it is the fastest way to see what building on this package actually
involves. Its server half is `examples/rps` in the engine repo, and the two are
checked against each other by shared JSON fixtures that both languages run.

RPS is deliberately the *hardest* small case: simultaneous commitment, hidden
information, and nothing worth predicting. So the example also shows the two
things a simpler game would hide — that an observation is a per-seat projection
rather than the state, and that `previewAction` returning null is sometimes the
correct answer.

```bash
cd example
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
```

## Documentation

| Doc | What it is |
|---|---|
| [`docs/client_reference.md`](docs/client_reference.md) | **Start here.** The client: transport and the frame stream, the Dart rules contract, the app shell, and everything involved in shipping an app (Firebase, assets, deep links, CI, store release). |
| `docs/architecture.md` in `eigen-server` | How the server works, end to end. |
| `docs/building_a_game.md` in `eigen-server` | The authoritative TypeScript rules contract — the other half of a game. |
| `docs/todo.md` in `eigen-server` | The single tracker for what's left, across both repos. |

## Layout

```
eigen-flutter/
├── lib/
│   ├── eigen_flutter.dart   # the public barrel — the ONLY thing an app imports
│   ├── app_runner.dart      # runEngineApp(...) entry point + root MyApp
│   ├── core/                # api (Dio + socket + clock), config, the game
│   │                        #   contract, navigation, notifications, analytics,
│   │                        #   storage, theme, connectivity, errors
│   ├── features/            # about auth game home profile rating settings social
│   ├── shared/              # shared widgets, providers, data
│   └── testing/             # the Dart half of the twin-fixture runner
├── example/                 # Rock–Paper–Scissors: a complete game, its own package
└── docs/client_reference.md

The generated REST client (`eigen_api`) is NOT here. It is generated and
published by the engine repo, which owns the wire contract, and consumed from
pub.dev like any other dependency.
```

## Using the engine in an app

Until this package is published to pub.dev, clone it as a **sibling** of your app
and depend on it by **path** — the same in local and CI:

```yaml
# in your app's pubspec.yaml
dependencies:
  eigen_flutter:
    path: ../eigen-flutter
```

Generated code (`*.g.dart`, `*.freezed.dart`) **is committed** — a fresh clone
compiles without a build step, and the published package ships it (consumers
never run `build_runner` on a dependency). Regenerate after changing any
annotated class; CI runs `build_runner` and fails if the result is not
committed.

```bash
cd eigen-flutter && flutter pub get
```

Then:

1. Implement a **Dart `GameModule`** (per-version `GameRules` units + the
   creation/about UI) under `lib/game/`, and register it in `main.dart` via
   `runEngineApp(module: const MyGameModule(), config: AppConfig(…), …)`.
2. Implement the matching **TypeScript `GameModule`** in your Worker — that is
   the authoritative half. Keep the two honest with shared twin fixtures.
3. Configure the app: `.env` (`API_BASE_URL` and friends), `flutterfire
   configure`, branding assets, deep-link host.

Full walkthrough in [`docs/client_reference.md`](docs/client_reference.md) —
Part II for the game contract, Part IV for shipping.

### One dependency, one import

An app depends on **`eigen_flutter` alone** and imports **only its barrel**:

```dart
import 'package:eigen_flutter/eigen_flutter.dart';
```

Never `package:eigen_api/...` (a generated build artifact the engine repo
rewrites wholesale) and never a deep path into `lib/`. The barrel re-exports the wire
types a game renders from — `GameStatus`, `Outcome`, `Player`, `Seat`, `Frame`,
… — while keeping the generated `*Api` classes and Dio out of your namespace:
**naming a type is part of the contract, calling the server is not.**
`test/core/architecture/api_isolation_test.dart` enforces both halves.

## Dev setup on a new machine

**Prerequisites**

| Tool | Version | Needed for |
|---|---|---|
| Flutter | 3.44.0 (stable) — matches CI | Everything |
| Dart SDK | ^3.9.2 (ships with Flutter) | Everything |
| JDK | 17 (Temurin) | Android builds |
| Xcode | latest | iOS builds (macOS only) |

No backend tooling is required to work on this package: it has no Docker
dependency, no local database, and no cloud account. It reads no config of its
own — an app injects everything at runtime.

```bash
git clone git@github.com:eigeninteractive/eigen-flutter.git
cd eigen-flutter
flutter pub get
flutter analyze              # generated code is committed — no build step needed
flutter test
```

Generated code is committed, so a fresh clone analyzes immediately. Re-run
`dart run build_runner build` after touching any annotated class — CI
regenerates and fails if you forgot to commit the result — or leave
`dart run build_runner watch` going while you work.

To work on an **app** against a local checkout of the engine, clone them as
siblings and run `build_runner` in the engine once (see the next section).

## Development

CI runs exactly what you can run locally, in this order — `dart format
--set-exit-if-changed`, `build_runner build`, `dart fix --apply` followed by
`git diff --exit-code`, `flutter analyze`, `flutter test`. There are no secrets
and no Firebase config in this repo's workflow, because the package reads none.

### The generated API client

`eigen_api` is generated from the engine's `openapi.json` **in the engine repo**
(`eigen-server/clients/dart`) and published to pub.dev at the engine's version.
Nothing here regenerates it, and there is no vendored copy of the spec: this
package just declares `eigen_api: ^1.0.0`.

That constraint is the compatibility statement. A server change that breaks the
wire is a major engine bump, so it becomes a visible, deliberate dependency bump
here rather than a silent drift between two copies of a file.

**To work on both halves at once**, clone `eigen-server` as a sibling and add a
`pubspec_overrides.yaml` (gitignored) pointing `eigen_api` at
`../eigen-server/clients/dart`. `flutter pub get` picks it up; the published
manifest never sees it.

**Wire enums are closed sets.** Generated enums carry no `unknown` sentinel and
parse strictly, so adding a member to any enum on the wire is a breaking change
needing a schema-version bump and a coordinated release. That is deliberate: it
turns a silent runtime failure into a loud build failure.
`test/shared/api_contract_test.dart` pins the sets.

## Versioning

This package and each app carry independent semvers; the engine is released as
git tags `vX.Y.Z` and versioned with [`cider`](https://pub.dev/packages/cider)
(`CHANGELOG.md` + `pubspec.yaml`).

```bash
cider log added "…"   # as you work
cider bump minor      # cut a release (major only once ≥ 1.0)
git commit -am "chore: release $(cider version)" \
  && git tag "v$(cider version)" && git push --tags
```

While at **0.y.z** the API is still evolving and breaking changes may land in a
MINOR bump. At **≥ 1.0.0**, MAJOR = a breaking Dart API or wire-contract change.

Three contracts can break across versions, each at a different layer:

1. **The Dart API** (the barrel, `runEngineApp`, the `GameModule`/`GameRules`
   contract) — breaks at **compile time**.
2. **The wire** (`openapi.json`, the closed enums, the socket protocol) — breaks
   at **runtime**, against server deployments *and* app binaries already on
   users' devices.
3. **Game payloads** (config / state / observation / action) — breaks
   **in-flight games**, and is handled by the per-`schema_version` `GameRules`
   units rather than in-place edits.

**Mobile update lag is the core constraint**: after you ship `v(n+1)`, users on
`v(n)` keep calling the same server for days or weeks. `client_reference.md` §25
covers the full policy — the three version axes, why draining gates the write
path while replay gates the read path, and the "I want to change the game"
checklist.
