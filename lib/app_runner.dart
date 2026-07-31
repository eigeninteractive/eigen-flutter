import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_flutter/core/api/retry_policy.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_flutter/core/navigation/providers/navigation_providers.dart';
import 'package:eigen_flutter/core/navigation/url_strategy.dart';
import 'package:eigen_flutter/core/startup/app_startup.dart';
import 'package:eigen_flutter/core/theme/app_theme.dart';
import 'package:eigen_flutter/core/theme/theme_provider.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';

/// Boots a whitelabel game app on the engine.
///
/// This is the framework's "app as a library" entry point: each game app's
/// `main()` is just a call to this with its [module], [config] and Firebase
/// wiring. It performs all engine-level initialisation (Firebase, crash/
/// analytics gating, fonts) and installs the two composition-root
/// overrides ([currentGameModuleProvider] and [appConfigProvider]).
///
/// [firebaseOptions] are the app's generated `DefaultFirebaseOptions`; they
/// live in the app package because `firebase_options.dart` is app-specific.
/// [onBackgroundMessage] must be a top-level (or static) function annotated
/// `@pragma('vm:entry-point')` — FCM runs it in a separate isolate, so it
/// cannot close over [firebaseOptions] and must re-init Firebase itself.
Future<void> runEngineApp({
  required GameModule module,
  required AppConfig config,
  required FirebaseOptions firebaseOptions,
  required Future<void> Function(RemoteMessage) onBackgroundMessage,
}) async {
  if (kIsWeb && config.engine.firebaseVapidKey.trim().isEmpty) {
    throw StateError(
      'FIREBASE_VAPID_KEY is required for Eigen web apps. '
      'Generate a Web Push certificate in Firebase Console and pass its '
      'public key with --dart-define=FIREBASE_VAPID_KEY=....',
    );
  }

  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategy();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Firebase.initializeApp(options: firebaseOptions);
  // Crash reporting and analytics are disabled in non-release builds so dev
  // events never reach production dashboards. Crashlytics has no web
  // implementation; browser errors remain visible in the console and hosting
  // observability instead of calling a missing platform channel at startup.
  if (!kIsWeb) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      kReleaseMode,
    );
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(kReleaseMode);
  // Web background delivery runs in firebase-messaging-sw.js, not a Dart
  // isolate. Registering this callback is only meaningful on native clients.
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
  }

  // The engine client needs no initialisation of its own: the HTTP client and
  // the game socket are built lazily from `config.engine.apiBaseUrl` by
  // `engineDioProvider`, and authenticate off whatever Firebase session
  // `Firebase.initializeApp` above restored.

  runApp(
    ProviderScope(
      // Narrows Riverpod's over-eager default retry to transport failures only
      // — a server-reported error is never re-run. See [engineProviderRetry].
      retry: engineProviderRetry,
      overrides: [
        currentGameModuleProvider.overrideWithValue(module),
        appConfigProvider.overrideWithValue(config),
      ],
      child: const AppStartup(child: MyApp()),
    ),
  );
}

/// Root application widget shared by every game built on the engine.
///
/// Reads the active [Branding] from [appConfigProvider] so the title and theme
/// follow whichever app registered the config.
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeAsync = ref.watch(themeControllerProvider);
    final themeMode = themeAsync.value ?? ThemeMode.system;
    final branding = ref.watch(appConfigProvider).branding;

    return MaterialApp.router(
      title: branding.appName,
      theme: AppTheme.light(branding.seedColor),
      darkTheme: AppTheme.dark(branding.seedColor),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
