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

## [0.3.5] - 2026-08-07
### Changed
- `configure_firebase` checks that a Google account is signed in to the Firebase CLI before it starts, and names `firebase login` when none is — those are the credentials both CLIs share, and previously the one preflight failure FlutterFire was left to discover for itself. The check fails open: only an answer that positively reports no accounts stops the run.
- A successful run names the Firebase project and the Android and Web app IDs it configured against. FlutterFire matches an existing Android app on the package name and an existing Web app on its display name, and reuses either without comment — so adopting the apps a project already had looked identical to registering new ones, and now does not.
- The Web SDK configuration is downloaded quietly. It is an intermediate — read, checked, rewritten as `web/firebase-config.js`, then deleted — so the Firebase CLI's own success line announced a temporary file that no longer existed by the time anyone read it. A failing download still prints everything it said.

## [0.3.4] - 2026-08-07
### Changed
- The credit line defaults to `Built with EigenInteractive`, matching the game's own website, and renders as prose with only the brand name linked — accent-coloured, no underline. A `Branding.madeByCredit` that never names the engine stays plain text. The settings and about screens now share one `MadeByCredit` widget instead of the same footer written twice.

### Fixed
- `configure_firebase` no longer fails with `FirebaseProjectRequiredException` on a first run: `--yes` is only passed once the Firebase project is settled, so an unconfigured run gets FlutterFire's project picker — where a project can also be created — instead of a hard stop. The project can be named with `--project <id>`, and is otherwise read back from the `firebase.json` a previous run wrote or a `.firebaserc`, so re-runs stay non-interactive. `--account <email>` is accepted for a machine signed in to several Google accounts, `--help` prints the usage, and a bare `--` is ignored so `run firebase:configure -- --project x` works under both npm and pnpm. Every other option is refused with a usage error rather than passed to FlutterFire: platforms in particular are fixed at Android and Web, which are the platforms the app has and where the messaging service worker's configuration comes from.

## [0.3.3] - 2026-08-07
### Changed
- Bundle Inter and Space Grotesk as single variable files instead of nine static Inter weights, and pair them across the Material 3 text roles: Space Grotesk on display and headline, Inter on everything read at length. `Branding.displayFontFamily` overrides the display face and `Branding.seedColor` now defaults to the EigenInteractive teal, so a game looks deliberate before anyone has configured it and is one line to rebrand. Font payload drops from 2.7 MB to under 1 MB while gaining a family, because `FontWeight` has driven the `wght` axis since Flutter 3.41 and this package requires 3.44 — `tool/download_fonts.sh`, which fetched static weights from gstatic by content hash, is gone.

## [0.3.2] - 2026-08-07
### Changed
- `configure_firebase` checks for `flutterfire` and `firebase` before it starts, and names the one that is missing with the command that installs it. It previously pointed at both CLIs without saying how to get either, and only after FlutterFire had already written its files.

## [0.3.1] - 2026-08-06
### Changed
- Use **EigenInteractive** as the product name in the package description, README, dartdoc and the default `madeByCredit` credit line. No API changes; the generated payload header comment now reads `Generated from the game-owned EigenInteractive contract.`, so a game running `generate_payloads --check` needs one regeneration.

## [0.3.0] - 2026-08-05
### Changed
- **Breaking for apps that customised the Firebase notification meta-data.**
The manifest merger treats two `<meta-data>` entries with the same
`android:name` and different `android:value` as a conflict and fails the build.
An app that declares
`com.google.firebase.messaging.default_notification_channel_id` or
`default_notification_icon` with a value other than `your_turn` /
`@drawable/ic_notification` must now either drop its copy — this package
supplies both — or keep it and add
`tools:replace="android:value"` (or `android:resource`) to that element.
Declaring the same values as this package needs no change.

### Fixed
- Notifications no longer need a hand-created icon. This package referenced
`@drawable/ic_notification` from its Dart while its Android plugin shipped no
resources at all, so the icon only resolved in apps that happened to create that
drawable themselves. The plugin now ships it, together with the Firebase
default-channel and default-notification-icon meta-data. An app overrides the
silhouette by declaring the same resource name — Android resource merging gives
the application module precedence over a library.

## [0.2.0] - 2026-08-03
### Changed
- `eigen_api` moved to `^0.2.0`, following the engine to its 0.2.x release line.
No Dart API changed — the 0.2.0 spec is byte-identical to 0.1.0's apart from
the version stamp, and 0.2.0 of the engine was a TypeScript-side cleanup — but
a consumer cannot depend on this package and `eigen_api 0.2.0` at the same
time until this ships, so it is a breaking change to the constraint rather
than a patch.

## [0.1.0] - 2026-08-02
Initial release. The entries below describe the starting state rather than
changes from a previous version.

### Added
- `configure_firebase`, which runs FlutterFire and generates the messaging
service worker's public Web configuration from the selected Firebase app.
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
Auth and notification capability share one required Firebase project; the
player permission prompt remains an explicit opt-in and delivery remains
best-effort.
- Avatar upload and display against the worker-served avatar URL, via
`cached_network_image`.
- Rock–Paper–Scissors under `example/` — a complete game, and the worked answer
to "how do I test a game screen". Its `fixtures/v1/rps.json` is the Dart half
of a twin-fixture contract the engine repo checks from the other side.
- **Inter** bundled as a package font (all 9 weights under `fonts:`), so
consuming apps get it automatically and it renders offline from the first
frame. `AppTheme` references `packages/eigen_flutter/Inter`.

### Changed
- Public app deployment values now use Dart compilation environment
declarations and one cross-platform `app-config.json`; startup reports
missing or malformed required values before initializing engine services.
- Persisted Riverpod API snapshots are native-only. Web keeps provider data for
the browser session and refetches after reload, while preferences, Firebase
Auth, and notification bookkeeping retain their own browser persistence.
- FCM registration now uses Firebase Installation IDs end-to-end. Web calls
Firebase's current `register` API through a narrow compatibility adapter;
Android uses native FID auto-registration configured by the package's Android
plugin, so consuming apps do not edit their generated manifest or Gradle
properties. The app no longer requests, refreshes, or persists deprecated
registration tokens.
- Notification opt-in is a contextual non-modal card for seated multiplayer
players. The platform permission state drives the UI directly; blocked users
get an explicit Settings recovery path.
- **The backend is the Eigen engine on Cloudflare Workers, not Supabase.** The
data layer talks to the Worker over REST and WebSocket; the transport half is
the generated `eigen_api` client, published from the engine repo at the
engine's own version and consumed here as an ordinary versioned dependency.
There is no vendored OpenAPI spec and no local codegen for it.
- Riverpod toolchain moved to the 3.3.2 line (`flutter_riverpod ^3.3.2`,
`riverpod_annotation ^4.0.3`, `riverpod_generator ^4.0.4`, `riverpod_lint ^3.1.4`, `riverpod_sqflite ^0.4.3`) so the engine resolves the same riverpod
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

[0.3.5]: https://github.com/eigeninteractive/eigen-flutter/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/eigeninteractive/eigen-flutter/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/eigeninteractive/eigen-flutter/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/eigeninteractive/eigen-flutter/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/eigeninteractive/eigen-flutter/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/eigeninteractive/eigen-flutter/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/eigeninteractive/eigen-flutter/compare/v0.1.0...v0.2.0
[0.1.0]: https://pub.dev/packages/eigen_flutter/versions/0.1.0
