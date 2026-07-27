# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries are maintained with [`cider`](https://pub.dev/packages/cider) — add them
as you work (`cider log added "…"`), and `cider release` moves everything under
`## [Unreleased]` into a dated section at release time.

Pre-1.0, breaking changes land in a **MINOR** bump: `^0.1.0` resolves to
`>=0.1.0 <0.2.0`. See
[Versions and compatibility](https://eigeninteractive.com/docs/reference/compatibility)
for how this package, the engine and the generated `eigen_api` client pair up.

## [Unreleased]

Initial release. Nothing has been published to pub.dev yet, so the entries below
describe the starting state rather than changes from a previous version.

### Added

- `runEngineApp(...)` entry point, with `AppConfig` / `EngineConfig` / `Branding`
  as the composition-root config. The framework reads every runtime value from
  `EngineConfig` and never from the app's `Env`, so this package needs no
  Firebase project or `.env` of its own.
- `Branding.madeByCredit`, so the settings footer credit is configurable.
- The `GameModule` / `GameRules` contract: a game supplies one rules unit per
  `schemaVersion`, and the framework dispatches on the version a game was
  created at.
- Client-side optimistic preview (`previewAction`) and cue-aware rendering
  against the engine's append-only observation history.
- Generated wire enums preserve values introduced by a newer server as an
  `unknownDefaultOpenApi` sentinel instead of failing response decoding. Known
  values retain their specific UI; unknown values degrade to generic UI when
  safe, while gameplay-critical values block only the affected surface and
  offer a native Play update on Android or a browser reload on web.
- Firebase auth (Google + guest), FCM push, Crashlytics and Analytics wiring.
- Avatar upload and display against the worker-served avatar URL, via
  `cached_network_image`.
- Rock–Paper–Scissors under `example/` — a complete game, and the worked answer
  to "how do I test a game screen". Its `fixtures/v1/rps.json` is the Dart half
  of a twin-fixture contract the engine repo checks from the other side.
- **Inter** bundled as a package font (all 9 weights under `fonts:`), so
  consuming apps get it automatically and it renders offline from the first
  frame. `AppTheme` references `packages/eigen_flutter/Inter`.

### Changed

- **The backend is the Eigen engine on Cloudflare Workers, not Supabase.** The
  data layer talks to the Worker over REST and WebSocket; the transport half is
  the generated `eigen_api` client, published from the engine repo at the
  engine's own version and consumed here as an ordinary versioned dependency.
  There is no vendored OpenAPI spec and no local codegen for it.
- Riverpod toolchain moved to the 3.3.2 line (`flutter_riverpod ^3.3.2`,
  `riverpod_annotation ^4.0.3`, `riverpod_generator ^4.0.4`, `riverpod_lint
  ^3.1.4`, `riverpod_sqflite ^0.4.3`) so the engine resolves the same riverpod
  core consuming apps do — generated code must be built against the core the app
  compiles against, and riverpod 3.3.x changed `Notifier.runBuild`'s signature.

### Removed

- The Supabase stack in full: `supabase_flutter`, the vendored
  `supabase/{migrations,functions,seed.sql,config.toml}`, the `sync_supabase`
  CLI that copied it into consuming apps, and the `update-ratings` /
  `refresh-fcm-token` edge functions. Ratings, notifications and every other
  server-side concern now live in the engine.
- `google_fonts`, which fetched Inter at runtime — replaced by the bundled
  package font above.
