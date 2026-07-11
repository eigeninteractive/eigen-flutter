import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_engine/core/analytics/analytics_provider.dart';
import 'package:eigen_engine/core/navigation/router/app_router.dart';
import 'package:eigen_engine/core/notifications/notification_provider.dart';
import 'package:eigen_engine/core/updates/update_notifier.dart';
import 'package:eigen_engine/features/auth/data/models/auth_user.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/game/providers/game_providers.dart';
import 'package:eigen_engine/features/profile/providers/profile_providers.dart';
import 'package:eigen_engine/features/social/providers/social_providers.dart';

/// Keeps the native splash screen visible until the auth state is known,
/// then hands control to [child] (which GoRouter routes normally).
class AppStartup extends ConsumerStatefulWidget {
  const AppStartup({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends ConsumerState<AppStartup> {
  late final AppLifecycleListener _lifecycleListener;
  late final ProviderSubscription<AsyncValue<AuthStateChange>> _authSub;
  StreamSubscription<String>? _notificationSub;

  @override
  void initState() {
    super.initState();
    _authSub = ref.listenManual(authStateChangesProvider, _onAuthStateChange);
    unawaited(_removeNativeSplashWhenReady());
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        ref.read(updateProvider.notifier).checkForUpdate();
        // Re-check permission in case the user changed it in system Settings.
        ref.invalidate(notificationPermissionStatusProvider);
      },
    );
    unawaited(_initNotifications());
  }

  /// Registers the navigation listener BEFORE initialize() so that the
  /// initial-message path (terminated-state tap) is never missed.
  Future<void> _initNotifications() async {
    final service = ref.read(notificationServiceProvider);
    _notificationSub = service.navigationStream.listen(
      _onNotificationNavigation,
    );
    try {
      await service.initialize();
    } catch (e, stack) {
      developer.log(
        'Notification service initialization failed',
        name: 'app.startup',
        error: e,
        stackTrace: stack,
      );
    }
  }

  @override
  void dispose() {
    _authSub.close();
    _notificationSub?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _removeNativeSplashWhenReady() async {
    try {
      final authState = await ref.read(authStateChangesProvider.future);
      // If authenticated, wait for the profile SQLite cache to restore before
      // revealing the home screen. Cap at 2 s — SQLite resolves in ~5 ms so
      // this only triggers when there is no local cache AND no network.
      if (authState.user != null) {
        await ref
            .read(currentUserProfileProvider.future)
            .timeout(const Duration(seconds: 2));
      }
    } catch (e, stack) {
      developer.log(
        'Startup initialization failed',
        name: 'app.startup',
        error: e,
        stackTrace: stack,
      );
    } finally {
      FlutterNativeSplash.remove();
    }
  }

  void _onAuthStateChange(
    AsyncValue<AuthStateChange>? _,
    AsyncValue<AuthStateChange> next,
  ) {
    next.whenOrNull(
      data: (authState) {
        final analytics = ref.read(analyticsServiceProvider);
        switch (authState.event) {
          case AuthEvent.initialSession:
          case AuthEvent.signedIn:
            if (authState.user case final user?) {
              unawaited(analytics.identify(user.id));
              // Segment all metrics by guest vs registered. Conversion later
              // re-tags to registered from AuthController.upgradeToGoogle.
              unawaited(analytics.setAccountType(isGuest: user.isAnonymous));
              // Register this install for push under the now-signed-in user.
              // Driven here (not in the service's one-time initialize) so an
              // in-session sign-in or account switch re-registers the new user.
              unawaited(
                ref.read(notificationServiceProvider).registerInstallation(),
              );
              // Fire-and-forget: starts the SQLite cache restore + network
              // fetch before any screen renders. keepAlive ensures the result
              // is reused by all subsequent watchers.
              ref.read(currentUserProfileProvider.future).ignore();
              // Warm the bot catalog the same way. The shell only watches it
              // when the build ships local bots (localBots.isNotEmpty short-
              // circuit), so this is what readies it for the server-bots-only
              // path (the waiting-room "Add bot" picker) before it is opened.
              ref.read(availableBotsProvider.future).ignore();
            }
          case AuthEvent.signedOut:
            unawaited(analytics.reset());
          case AuthEvent.tokenRefreshed:
          case AuthEvent.userUpdated:
          case AuthEvent.other:
            break;
        }
      },
    );
  }

  void _onNotificationNavigation(String path) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    if (path.startsWith('/social')) {
      ref.invalidate(friendshipsProvider);
    }
    GoRouter.of(context).navigateFromNotification(path);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
