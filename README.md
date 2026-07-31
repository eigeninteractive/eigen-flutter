# Eigen Flutter

The Flutter half of [Eigen](https://eigeninteractive.com): a
server-authoritative engine for turn-based multiplayer games.

`eigen_flutter` supplies the complete app shell—authentication, lobbies,
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
configuration. Eigen's standard app targets Android and web, so the public Web
Push key is required deployment configuration; it belongs to the same Firebase
project used for authentication:

```dart
Future<void> main() => runEngineApp(
  module: const MyGameModule(),
  config: const AppConfig(
    branding: Branding(appName: 'My Game', seedColor: Colors.indigo),
    engine: EngineConfig(
      apiBaseUrl: 'https://game.example.com',
      googleWebClientId: 'your-client-id.apps.googleusercontent.com',
      firebaseVapidKey: const String.fromEnvironment('FIREBASE_VAPID_KEY'),
    ),
  ),
  firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  onBackgroundMessage: onBackgroundMessage,
);
```

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
