import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_flutter/core/navigation/router/app_router.dart';
import 'package:eigen_flutter/core/navigation/utils/stream_listenable.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';

part 'navigation_providers.g.dart';

/// Provider for the GoRouter instance with auth-based routing
/// Keep alive ensures the router is never disposed during app lifetime
///
/// Uses StreamListenable to automatically redirect when auth state changes
@Riverpod(keepAlive: true)
GoRouter goRouter(Ref ref) {
  final authService = ref.watch(authServiceProvider);

  final refreshListenable = StreamListenable(authService.authStateChanges);
  ref.onDispose(() => refreshListenable.dispose());

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    debugLogDiagnostics: false, // Disabled for performance
    // go_router listens to this and re-evaluates redirects on auth changes
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authService = ref.read(authServiceProvider);
      final isAuthenticated = authService.currentUser != null;
      final isGoingToLogin = state.matchedLocation == '/login';

      // Not authenticated → redirect to login, preserving the intended
      // destination so deep links survive the auth flow.
      if (!isAuthenticated && !isGoingToLogin) {
        final destination = state.uri.toString();
        final encoded = Uri.encodeComponent(destination);
        return '/login?redirect=$encoded';
      }

      // Authenticated and on the login page → go to the preserved destination
      // (e.g. a /join/:code deep link) or fall back to home.
      if (isAuthenticated && isGoingToLogin) {
        final redirectTo = state.uri.queryParameters['redirect'];
        if (redirectTo != null && redirectTo.isNotEmpty) {
          return Uri.decodeComponent(redirectTo);
        }
        return '/home';
      }

      // Social is registered-only. Bounce guests reaching it (deep link or
      // post-sign-out race) back home; the upgrade nudge lives in settings.
      final isGuest = authService.currentUser?.isAnonymous ?? false;
      if (isGuest && state.matchedLocation.startsWith('/social')) {
        return '/home';
      }

      return null;
    },
    onException: (context, state, router) {
      // Unknown paths (e.g. a deep link the OS re-routes into the app for a
      // path we don't handle) go home rather than crashing with GoException.
      router.go('/home');
    },
    routes: appRoutes,
    observers: [
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
  );
}
