import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:eigen_flutter/core/navigation/providers/navigation_providers.dart';
import 'package:eigen_flutter/core/notifications/firebase_notification_service.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:eigen_flutter/shared/providers/device_installation_providers.dart';

part 'notification_provider.g.dart';

/// Application-wide [FirebaseNotificationService] instance.
@Riverpod(keepAlive: true)
FirebaseNotificationService notificationService(Ref ref) =>
    FirebaseNotificationService(
      messaging: FirebaseMessaging.instance,
      installations: FirebaseInstallations.instance,
      installationRepository: ref.watch(deviceInstallationRepositoryProvider),
      localNotifications: FlutterLocalNotificationsPlugin(),
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

/// Current notification permission status.
///
/// Auto-disposes so it is re-fetched on demand. Invalidate this provider
/// in [AppLifecycleListener.onResume] so the Settings screen reflects any
/// changes the user made in system Settings while the app was backgrounded.
@riverpod
Future<AuthorizationStatus> notificationPermissionStatus(Ref ref) async {
  final settings = await FirebaseMessaging.instance.getNotificationSettings();
  return settings.authorizationStatus;
}
