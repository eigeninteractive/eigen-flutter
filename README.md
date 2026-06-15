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

See [`docs/game_implementation_guide.md`](docs/game_implementation_guide.md) and
[`docs/versioning.md`](docs/versioning.md).
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
│   └── sync_migrations.dart # CLI: assembles an app's supabase/migrations from packages
├── supabase/migrations/     # canonical framework/infra migrations
└── docs/                    # engine_architecture.md, game_implementation_guide.md
```

## Using the engine in an app

1. Add the `eigen_engine` dependency (above) to your app.
2. Implement a `GameModule` (rules engine + content widget + models) under
   `lib/game/` and its five SQL hooks; register it in `main.dart` via
   `runEngineApp(module: const MyGameModule(), config: AppConfig(…), …)`.
3. Vendor the engine's migrations into your committed `supabase/migrations/`
   (alongside your game hook): `dart run eigen_engine:sync_migrations`.

The full walkthrough — project structure, the `GameModule` contract, the SQL
hooks, timing, ratings, deep links — is in
[`docs/game_implementation_guide.md`](docs/game_implementation_guide.md).
[`docs/engine_architecture.md`](docs/engine_architecture.md) explains how the
engine works internally, [`docs/versioning.md`](docs/versioning.md) covers
versioning + backward compatibility (how the engine and apps evolve in
production), and [`docs/future_plans.md`](docs/future_plans.md) tracks planned
engine capabilities (bots, spectating, simultaneous-move games).

## Development

```bash
dart pub get
dart run build_runner build
flutter analyze
```

Versioned with [`cider`](https://pub.dev/packages/cider) (`CHANGELOG.md` +
`pubspec.yaml`).
