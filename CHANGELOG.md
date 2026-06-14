# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-15

Initial standalone release. Versioning + backward-compatibility policy:
[`docs/versioning.md`](docs/versioning.md). Pre-1.0 — the API may change in
MINOR bumps until `1.0.0`.

### Added

- Extracted Eigen Engine into its own repository from the original monorepo
  (history preserved). Consumed by game apps via a path (dev) or git-tag
  (release) dependency.
- `runEngineApp(...)` entry point; `AppConfig`/`EngineConfig`/`Branding`
  composition-root config (the framework reads runtime values from
  `EngineConfig`, never the app's `Env`).
- `Branding.madeByCredit` so the settings footer credit is configurable.
- `sync_migrations` CLI that vendors the engine's migrations into a consuming
  app's committed `supabase/migrations/`.

### Changed

- `Supabase.initialize` uses `publishableKey:` (supabase_flutter 2.14 deprecated
  `anonKey`); the config field is `EngineConfig.supabasePublishableKey`.
