<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://eigeninteractive.com/brand/eigen-lockup-dark-360.png">
  <img src="https://eigeninteractive.com/brand/eigen-lockup-360.png" alt="EigenInteractive" width="270">
</picture>

# EigenInteractive Flutter

The Flutter half of [EigenInteractive](https://eigeninteractive.com): a
server-authoritative engine for turn-based multiplayer games.

`eigen_flutter` supplies the complete app shell: authentication, lobbies,
reconnection, timing, ratings, history, replay, social features, notifications,
deep links, and update UX. A game supplies a small `GameModule` containing its
client-side rules and presentation.

## Start a game

The recommended flow creates the Cloudflare Worker and Flutter app together:

```bash
pnpm create eigen-game my-game
# or
npm create eigen-game@latest my-game
```

The scaffold installs published npm/pub.dev dependencies; it does not clone the
engine repositories. For an existing app or separate Worker/app repositories,
follow the [manual setup guide](https://eigeninteractive.com/docs/getting-started/manual-setup).

## Add to an app

```yaml
dependencies:
  eigen_flutter: ^0.1.0
  firebase_core: ^4.9.0
  firebase_messaging: ^16.2.0
```

Import the framework through its public barrel:

```dart
import 'package:eigen_flutter/eigen_flutter.dart';
```

Do not depend on `eigen_api` directly or deep-import `core/`, `features/`, or
`shared/`. The barrel is the supported game-facing API.

On Android, `flutter_local_notifications` requires core-library desugaring in
the application module. `create-eigen-game` configures it automatically. For a
hand-created app, add this to `android/app/build.gradle.kts`:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Boot the app with your module, branding, Worker origin, and generated Firebase
configuration. The standard app targets Android and web, so the public Web
Push key is required deployment configuration; it belongs to the same Firebase
project used for authentication:

```dart
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
const appHost = String.fromEnvironment('APP_HOST');

Future<void> main() => runEngineApp(
  module: const MyGameModule(),
  config: AppConfig(
    branding: const Branding(appName: 'My Game', seedColor: Colors.indigo),
    engine: EngineConfig(
      apiBaseUrl: apiBaseUrl,
      googleWebClientId: googleWebClientId,
      firebaseVapidKey: firebaseVapidKey,
      appHost: appHost.isEmpty ? null : appHost,
    ),
  ),
  firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  onBackgroundMessage: onBackgroundMessage,
);
```

These are public build-time values. Scaffolded apps keep them in
`app-config.json` and use the same command option for Android and web:

```bash
flutter run --dart-define-from-file=app-config.json
```

Missing or malformed required values are reported together before Firebase or
any engine service starts. Keep actual secrets on the Worker.

Connect a game app to Firebase with the package executable:

```bash
dart run eigen_flutter:configure_firebase
```

It runs FlutterFire for Android and web, then derives
`web/firebase-config.js` for the messaging service worker from the Web app
FlutterFire selected. The public VAPID key remains in `app-config.json` because
it is not part of Firebase's app SDK configuration.

## The game boundary

The authoritative TypeScript module declares `state`, `observation`, `action`,
and `config` once. It emits `game-contract.json`; this package's executable
turns that artifact into immutable Dart payloads, a typed rules base, and
fixture copies:

```bash
dart run eigen_flutter:generate_payloads \
  --contract ../server/game-contract.json \
  --output lib/game/generated/payloads.dart \
  --fixtures-output test/fixtures
```

Your handwritten Dart code then:

- extends the generated `V<N>RulesBase`;
- implements client-side legality and optional optimistic preview;
- renders the game from `GameContentContext`;
- registers one rules unit per server `schemaVersion`;
- declares the version-independent creation and rules UI.

The server remains authoritative. Shared fixtures run against both languages so
payload and behavior drift fails in tests.

## Example

[`example/`](example/) is a complete Rock–Paper–Scissors client. It deliberately
uses simultaneous hidden commitments to demonstrate per-seat observations and
the valid “do not predict this move” path:

```bash
cd example
flutter pub get
flutter test
flutter build web --release
```

The package treats Android and web as supported targets. The generated scaffold
includes the browser Firebase Messaging service worker, Firebase Auth's web
popup flow, cross-origin Worker setup, and a release web build in CI. See
[Deploy the web app](https://eigeninteractive.com/docs/ship-it/deploy-the-web-app).

## Documentation

- [Quickstart](https://eigeninteractive.com/docs/getting-started/quickstart)
- [The TypeScript + Dart game contract](https://eigeninteractive.com/docs/build-a-game/the-contract)
- [Payload generation](https://eigeninteractive.com/docs/build-a-game/schemas)
- [Rendering a game](https://eigeninteractive.com/docs/build-a-game/rendering)
- [Testing both halves](https://eigeninteractive.com/docs/build-a-game/testing)
- [Deploy the web app](https://eigeninteractive.com/docs/ship-it/deploy-the-web-app)
- [Dart API reference](https://pub.dev/documentation/eigen_flutter/latest/)
- [Versions and compatibility](https://eigeninteractive.com/docs/reference/compatibility)

## Working on the framework

- [CONTRIBUTING.md](CONTRIBUTING.md): local setup, generation, validation,
  changelog entries, and pull requests.
- [MAINTAINERS.md](MAINTAINERS.md): pub.dev setup, releases, version tags, and
  failure recovery.
