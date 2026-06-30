# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Bundle **Inter** as a package font (all 9 weights under `fonts:`) instead of
  fetching it at runtime via `google_fonts`; dropped the `google_fonts`
  dependency. Consuming apps get Inter automatically and it renders offline from
  the first frame. `AppTheme` references `packages/eigen_engine/Inter`.
- Bumped the riverpod toolchain to the 3.3.2 line (`flutter_riverpod ^3.3.2`,
  `riverpod_annotation ^4.0.3`, `riverpod_generator ^4.0.4`, `riverpod_lint
  ^3.1.4`, `riverpod_sqflite ^0.4.3`) so the engine resolves the same riverpod
  core that consuming apps do — generated code must be built against the core the
  app compiles against (riverpod 3.3.x changed `Notifier.runBuild`'s signature).

## [0.1.0] - 2026-06-15

Initial standalone release. Versioning + backward-compatibility policy:
[README → Versioning & backward compatibility](README.md#versioning--backward-compatibility).
Pre-1.0 — the API may change in MINOR bumps until `1.0.0`.

### Added

- Extracted Eigen Engine into its own repository from the original monorepo
  (history preserved). Consumed by game apps via a path (dev) or git-tag
  (release) dependency.
- `runEngineApp(...)` entry point; `AppConfig`/`EngineConfig`/`Branding`
  composition-root config (the framework reads runtime values from
  `EngineConfig`, never the app's `Env`).
- `Branding.madeByCredit` so the settings footer credit is configurable.
- `sync_supabase` CLI that vendors the engine's backend (migrations, edge
  functions, seed) into a consuming app's committed `supabase/`.
- Engine backend lives in the engine repo: `supabase/{migrations,functions,seed.sql,config.toml}`
  (the edge functions `update-ratings` + `refresh-fcm-token`, the seed, and a
  reference `config.toml`).

### Changed

- `Supabase.initialize` uses `publishableKey:` (supabase_flutter 2.14 deprecated
  `anonKey`); the config field is `EngineConfig.supabasePublishableKey`.
