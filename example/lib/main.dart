/// The entire app.
///
/// Every screen a player sees (sign-in, home, the lobby, friends, profile,
/// settings, history, replay, push permission prompts) comes from
/// `eigen_flutter`. What an app supplies is this file: which game to play,
/// what it is called, what colour it is, and where its server lives.
///
/// To run it against a real server you need two things this repository
/// deliberately does not contain: a Firebase project and a deployed
/// EigenInteractive worker (see the RPS example Worker in
/// `eigen-server/examples/rps`). Run the
/// package's Firebase configuration executable and fill `app-config.json`
/// before running it.
library;

import 'package:eigen_flutter/eigen_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'rps.dart';

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const _firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
const _appHost = String.fromEnvironment('APP_HOST');

Future<void> main() async {
  await runEngineApp(
    // The game. One value, one line: the seam the whole framework is
    // built around.
    module: const RpsModule(),
    config: AppConfig(
      branding: const Branding(
        appName: 'Rock Paper Scissors',
        seedColor: Colors.teal,
      ),
      engine: EngineConfig(
        // Origin only: every route already carries its `/api/engine` prefix,
        // and the game socket is this same origin with the scheme swapped to
        // `wss`. These public build-time values are injected once here rather
        // than read throughout the framework.
        apiBaseUrl: _apiBaseUrl,
        googleWebClientId: _googleWebClientId,
        appHost: _appHost.isEmpty ? null : _appHost,
        firebaseVapidKey: _firebaseVapidKey,
      ),
    ),
    firebaseOptions: DefaultFirebaseOptions.currentPlatform,
    onBackgroundMessage: _onBackgroundMessage,
  );
}

/// FCM delivers background messages on a separate isolate, so this must be a
/// top-level function marked as an entry point and must re-initialise Firebase
/// itself; it cannot close over anything from [main].
///
/// The engine's notifications carry their own display payload, so there is
/// nothing to do here beyond making the isolate valid.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}
