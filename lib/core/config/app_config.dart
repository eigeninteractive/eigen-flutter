import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_config.g.dart';

/// Whitelabel configuration for one game app built on the engine.
///
/// The single composition-root config object, set once via [appConfigProvider]
/// by [runEngineApp]. It groups the app's configurable concerns by
/// responsibility:
///
/// - [branding] — user-facing identity (name, theme seed).
/// - [engine] — runtime backend/integration values the framework needs.
///
/// Keeping each concern as its own value object is what stops this from
/// decaying into a junk drawer of unrelated flags. The app reads its
/// compile-time secrets from `Env` (envied) and passes them in here, so the
/// framework never depends on the app's `Env` directly — the seam that lets the
/// framework live in its own package.
@immutable
class AppConfig {
  const AppConfig({required this.branding, required this.engine});

  /// User-facing identity: app name and theme seed color.
  final Branding branding;

  /// Backend and integration values the framework needs at runtime.
  final EngineConfig engine;
}

/// Runtime configuration the framework needs to talk to its backends.
///
/// These values originate as compile-time secrets in the app's `Env` (envied)
/// and are injected here at the composition root, so framework code reads them
/// from [appConfigProvider] instead of importing the app's `Env`.
@immutable
class EngineConfig {
  const EngineConfig({
    required this.apiBaseUrl,
    required this.googleWebClientId,
    required this.firebaseVapidKey,
    this.appHost,
  });

  /// Origin of the Eigen server, with no trailing slash and no path — for
  /// example `https://api.example.com`.
  ///
  /// Only the origin: every generated route already carries the `/api/engine`
  /// prefix, and the game socket is built from this same origin with the scheme
  /// swapped to `ws`/`wss`.
  final String apiBaseUrl;

  /// Google Sign-In web/server client id.
  final String googleWebClientId;

  /// VAPID public key for FCM Web Push.
  ///
  /// Eigen's standard app targets Android and web, so notification capability
  /// is part of the deployment contract rather than an optional integration.
  /// Android does not consume this value; web startup rejects an empty key.
  /// The key is public and belongs to the same Firebase project as Auth.
  final String firebaseVapidKey;

  /// The game's public host, e.g. `strategy.eigeninteractive.com` or a
  /// customer's own domain; null disables the features built on it.
  ///
  /// One host serves everything: the app's deep links (`/join/:code`,
  /// `/game/:id`), and — when the worker has `site` configured — the legal
  /// pages and landing page. The App Links intent-filter is scoped to the
  /// deep-link prefixes, so legal URLs on this same host open in the browser
  /// rather than being intercepted.
  final String? appHost;
}

/// User-facing identity for the app shell.
///
/// Everything brandable from Dart: the name shown in the window title, drawer
/// header and login screen, and the Material 3 seed color the entire theme is
/// derived from. (App icon, splash screen and store assets are platform files
/// configured outside Dart.)
@immutable
class Branding {
  const Branding({
    required this.appName,
    required this.seedColor,
    this.madeByCredit = 'Made with ❤️ by Eigen Interactive',
  });

  /// User-facing application name (window title, drawer header, login screen).
  final String appName;

  /// Material 3 seed color; the full light/dark [ColorScheme] derives from it.
  final Color seedColor;

  /// Credit line shown in the settings footer. Defaults to the Eigen
  /// Interactive umbrella credit; override per app if needed.
  final String madeByCredit;
}

/// The active [AppConfig].
///
/// [runEngineApp] registers the config for normal apps. Widget tests that
/// construct their own `ProviderScope` can override it directly:
/// ```dart
/// appConfigProvider.overrideWithValue(
///   AppConfig(
///     branding: const Branding(
///       appName: 'Tic Tac Toe',
///       seedColor: Colors.deepPurple,
///     ),
///     engine: EngineConfig(
///       apiBaseUrl: Env.apiBaseUrl,
///       googleWebClientId: Env.googleWebClientId,
///       firebaseVapidKey: Env.firebaseVapidKey,
///     ),
///   ),
/// )
/// ```
/// Throws [UnimplementedError] at startup if no override is provided.
@Riverpod(keepAlive: true)
AppConfig appConfig(Ref ref) => throw UnimplementedError(
  'No AppConfig registered. '
  'Add appConfigProvider.overrideWithValue(...) to ProviderScope.',
);
