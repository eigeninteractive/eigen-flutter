import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:eigen_flutter/core/navigation/providers/navigation_providers.dart';
import 'package:eigen_flutter/core/notifications/firebase_notification_service.dart';
import 'package:eigen_flutter/core/notifications/firebase_messaging_registration_factory.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:eigen_flutter/shared/providers/device_installation_providers.dart';

part 'notification_provider.g.dart';

/// Presentation state for the notification nudge in a multiplayer waiting room.
enum NotificationNudgeState {
  /// Nothing should be rendered.
  hidden,

  /// Explain the benefit and offer an inline permission action.
  enable,

  /// Permission is blocked; explain how to restore it in platform settings.
  openSettings,
}

/// Resolves permission state into waiting-room UI.
@visibleForTesting
NotificationNudgeState resolveNotificationNudgeState({
  required NotificationPermissionState permissionState,
}) => switch (permissionState) {
  NotificationPermissionState.unavailable ||
  NotificationPermissionState.enabled => NotificationNudgeState.hidden,
  NotificationPermissionState.promptable => NotificationNudgeState.enable,
  NotificationPermissionState.blocked => NotificationNudgeState.openSettings,
};

/// Application-wide [FirebaseNotificationService] instance.
@Riverpod(keepAlive: true)
FirebaseNotificationService notificationService(Ref ref) =>
    FirebaseNotificationService(
      messaging: FirebaseMessaging.instance,
      messagingRegistration: createFirebaseMessagingRegistration(
        FirebaseMessaging.instance,
        FirebaseInstallations.instance,
      ),
      installations: FirebaseInstallations.instance,
      installationRepository: ref.watch(deviceInstallationRepositoryProvider),
      localNotifications: FlutterLocalNotificationsPlugin(),
      preferences: SharedPreferencesAsync(),
      currentUserId: () => ref.read(authServiceProvider).currentUser?.id,
      activeGameId: () {
        final uri = ref
            .read(goRouterProvider)
            .routerDelegate
            .currentConfiguration
            .uri;
        final segments = uri.pathSegments;
        return (segments.length == 2 && segments[0] == 'game')
            ? segments[1]
            : null;
      },
      vapidKey: ref.watch(appConfigProvider).engine.firebaseVapidKey,
    );

/// Current app-facing notification permission and capability state.
///
/// Auto-disposes so it is re-fetched on demand. Invalidate this provider
/// in [AppLifecycleListener.onResume] so the Settings screen reflects any
/// changes the user made in system Settings while the app was backgrounded.
@riverpod
Future<NotificationPermissionState> notificationPermissionStatus(Ref ref) =>
    ref.watch(notificationServiceProvider).permissionState();

/// Notification nudge appropriate for this install's next waiting-room frame.
@riverpod
Future<NotificationNudgeState> notificationNudge(Ref ref) async {
  final permissionState = await ref.watch(
    notificationPermissionStatusProvider.future,
  );
  return resolveNotificationNudgeState(permissionState: permissionState);
}
