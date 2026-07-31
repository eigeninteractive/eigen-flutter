/// The entire app.
///
/// Every screen a player sees — sign-in, home, the lobby, friends, profile,
/// settings, history, replay, push permission prompts — comes from
/// `eigen_flutter`. What an app supplies is this file: which game to play,
/// what it is called, what colour it is, and where its server lives.
///
/// To run it against a real server you need two things this repository
/// deliberately does not contain: a Firebase project (`flutterfire configure`
/// writes `firebase_options.dart`) and a deployed Eigen worker (see the RPS
/// example Worker in `eigen-server/examples/rps`). Replace [_firebaseOptions]
/// and `apiBaseUrl` below with yours.
library;

import 'package:eigen_flutter/eigen_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'rps.dart';

const _firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

Future<void> main() async {
  await runEngineApp(
    // The game. One value, one line — this is the seam the whole framework is
    // built around.
    module: const RpsModule(),
    config: AppConfig(
      branding: const Branding(
        appName: 'Rock Paper Scissors',
        seedColor: Colors.teal,
      ),
      engine: const EngineConfig(
        // Origin only: every route already carries its `/api/engine` prefix,
        // and the game socket is this same origin with the scheme swapped to
        // `wss`. In a real app these come from compile-time secrets (envied)
        // rather than literals, which is what `EngineConfig` exists for.
        apiBaseUrl: 'https://rps.example.com',
        googleWebClientId: 'REPLACE_ME.apps.googleusercontent.com',
        appHost: 'rps.example.com',
        firebaseVapidKey: _firebaseVapidKey,
      ),
    ),
    firebaseOptions: _firebaseOptions,
    onBackgroundMessage: _onBackgroundMessage,
  );
}

/// Placeholder. Delete this and import the `DefaultFirebaseOptions` that
/// `flutterfire configure` generates into `lib/firebase_options.dart` — a file
/// that is app-specific and, like every other Firebase artifact, gitignored.
const _firebaseOptions = FirebaseOptions(
  apiKey: 'REPLACE_ME',
  appId: 'REPLACE_ME',
  messagingSenderId: 'REPLACE_ME',
  projectId: 'REPLACE_ME',
);

/// FCM delivers background messages on a separate isolate, so this must be a
/// top-level function marked as an entry point and must re-initialise Firebase
/// itself — it cannot close over anything from [main].
///
/// The engine's notifications carry their own display payload, so there is
/// nothing to do here beyond making the isolate valid.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: _firebaseOptions);
}
