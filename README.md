# Eigen Engine

A Flutter + Supabase **whitelabel engine** for turn-based multiplayer games
(auth, realtime, timing, ratings, social, notifications). A game plugs in as a
single Dart `GameModule` plus a handful of SQL hooks; an app boots with
`runEngineApp(...)`.

This is a **standalone package** with no bundled example game. Game apps live in
their own repos (e.g. `strategy`, `bravado`) and consume the engine via a
relative path dependency:

```yaml
# in a game/app pubspec.yaml (repos kept as siblings)
dependencies:
  eigen_engine:
    path: ../../../eigen_engine
```

This keeps engine edits picked up instantly during local development — no
commit/tag cycle.

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

1. Add the path dependency (above) in the game package and the app package.
2. Implement a `GameModule` in the game package; register it in the app's
   `main.dart` via `runEngineApp(module: const MyGameModule(), config: AppConfig(…), …)`.
3. Assemble migrations from the app directory:
   `dart run eigen_engine:sync_migrations --game <my_game>`.

See [`docs/game_implementation_guide.md`](docs/game_implementation_guide.md) and
[`docs/engine_architecture.md`](docs/engine_architecture.md).

## Development

```bash
dart pub get
dart run build_runner build
flutter analyze
```

Versioned with [`cider`](https://pub.dev/packages/cider) (`CHANGELOG.md` +
`pubspec.yaml`).
