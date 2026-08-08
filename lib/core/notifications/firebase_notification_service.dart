import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:eigen_flutter/core/notifications/firebase_messaging_registration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eigen_flutter/shared/data/device_installation_repository.dart';

// ── Android notification channels ────────────────────────────────────────────
// Each channel appears as an independent toggle in Android system settings,
// giving users per-category control without any in-app preference tracking.

const _yourTurnChannel = AndroidNotificationChannel(
  'your_turn',
  'Your Turn',
  description: 'Alerts when it\'s your move in an active game.',
  importance: Importance.high,
);

const _gameChannel = AndroidNotificationChannel(
  'game_updates',
  'Game Updates',
  description: 'Your game is ready to start, or a match has finished.',
  importance: Importance.defaultImportance,
);

const _gameInvitesChannel = AndroidNotificationChannel(
  'game_invites',
  'Game Invites',
  description: 'A friend started a game you can join.',
  importance: Importance.defaultImportance,
);

const _socialChannel = AndroidNotificationChannel(
  'social_notifications',
  'Social & Friends',
  description: 'Friend requests and social updates.',
  importance: Importance.low,
);

/// Catch-all for a category this build does not recognise, e.g. a newer server
/// than the installed app. Nothing is dropped; it surfaces here instead.
const _generalChannel = AndroidNotificationChannel(
  'general',
  'General',
  description: 'Other notifications.',
  importance: Importance.defaultImportance,
);

// ── Notification category ─────────────────────────────────────────────────────

enum _NotificationCategory {
  yourTurn,
  gameReady,
  gameFinished,
  gameInvite,
  friendRequest,
  friendAccepted;

  /// Parses the `category` field from the FCM data payload: the exact set the
  /// engine sends (see the server's `push.ts`). Returns null for an unknown or
  /// missing value (a newer server than this build); the caller falls back to a
  /// generic notification rather than dropping it.
  static _NotificationCategory? fromString(String? value) => switch (value) {
    'yourTurn' => yourTurn,
    'gameReady' => gameReady,
    'gameFinished' => gameFinished,
    'gameInvite' => gameInvite,
    'friendRequest' => friendRequest,
    'friendAccepted' => friendAccepted,
    _ => null,
  };
}

/// App-facing notification permission and capability state.
///
/// Firebase's [AuthorizationStatus.denied] is ambiguous on Android 13+: it can
/// mean either "not asked yet" or "the user denied the prompt". The service
/// combines it with whether this app has made a user-initiated request so the
/// Settings UI can offer the right next action.
enum NotificationPermissionState {
  /// Messaging is unsupported in this browser.
  ///
  /// A missing VAPID key is a deployment error caught by `runEngineApp`, not a
  /// player-facing capability state.
  unavailable,

  /// The app can ask, and has not received a decision yet.
  promptable,

  /// Notifications are authorized (including Apple's provisional grant).
  enabled,

  /// Permission was denied or subsequently disabled in system/browser settings.
  blocked,
}

/// Permission was granted, but FCM or server registration could not be
/// completed. The service retries when the app resumes.
final class NotificationRegistrationException implements Exception {
  const NotificationRegistrationException([this.cause]);

  final Object? cause;

  @override
  String toString() => 'NotificationRegistrationException: $cause';
}

/// Resolves Firebase's platform status into the state the UI needs.
@visibleForTesting
NotificationPermissionState resolveNotificationPermissionState({
  required AuthorizationStatus authorizationStatus,
  required bool available,
  required bool isAndroid,
  required bool hasRequestedPermission,
}) {
  if (!available) return NotificationPermissionState.unavailable;
  return switch (authorizationStatus) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => NotificationPermissionState.enabled,
    AuthorizationStatus.notDetermined => NotificationPermissionState.promptable,
    AuthorizationStatus.denied =>
      isAndroid && !hasRequestedPermission
          ? NotificationPermissionState.promptable
          : NotificationPermissionState.blocked,
  };
}

// ── Service ───────────────────────────────────────────────────────────────────

/// FCM push notification service using Firebase Cloud Messaging.
class FirebaseNotificationService {
  FirebaseNotificationService({
    required this._messaging,
    required this._messagingRegistration,
    required this._installations,
    required this._installationRepository,
    required this._localNotifications,
    required this._preferences,
    required this._activeGameId,
    required this._currentUserId,
    required this._vapidKey,
  });

  final FirebaseMessaging _messaging;
  final FirebaseMessagingRegistration _messagingRegistration;
  final FirebaseInstallations _installations;
  final DeviceInstallationRepository _installationRepository;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final SharedPreferencesAsync _preferences;
  final String? Function() _activeGameId;

  /// Reads the signed-in user's id at call time (null when signed out), so
  /// registration follows the live session without holding an auth handle.
  final String? Function() _currentUserId;

  /// Public VAPID key for FCM Web Push, injected from [EngineConfig].
  final String _vapidKey;

  final StreamController<String> _nav = StreamController<String>.broadcast();
  bool _initialized = false;
  Future<void>? _initializing;
  Future<bool>? _availability;

  /// SharedPreferences key holding the last-registered `userId:fid`, used to
  /// know whether permission revocation needs server cleanup.
  static const _registeredKey = 'notifications_registered_installation';
  static const _permissionRequestedKey = 'notifications_permission_requested';

  Stream<String> get navigationStream => _nav.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    final pending = _initializing;
    if (pending != null) return pending;
    final initialization = _initialize();
    _initializing = initialization;
    try {
      await initialization;
      _initialized = true;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize() async {
    if (!kIsWeb) {
      await _createChannels();

      // iOS: show banners while the app is foregrounded.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          // Permission is requested exclusively via
          // FirebaseMessaging.requestPermission() after an explicit UI action.
          // Setting these flags to false prevents flutter_local_notifications
          // from issuing a duplicate iOS dialog during initialization.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) _nav.add(payload);
        },
      );
    }

    _messagingRegistration.registeredFids.listen((fid) async {
      try {
        await _register(fid: fid);
      } catch (error, stackTrace) {
        developer.log(
          'FCM registration callback upload failed; will retry',
          name: 'notifications',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
    _messagingRegistration.unregisteredFids.listen((fid) async {
      try {
        await _installationRepository.delete(fid: fid);
        final marker = await _preferences.getString(_registeredKey);
        if (marker?.endsWith(':$fid') == true) {
          await _preferences.remove(_registeredKey);
        }
      } catch (error, stackTrace) {
        developer.log(
          'FCM unregistration callback cleanup failed; will retry',
          name: 'notifications',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });

    // Initialization never asks for permission. If a previous user gesture
    // already granted it, restore the FCM registration; otherwise the
    // contextual waiting-room action or Settings owns the request.
    await syncPermissionAndRegistration();

    if (!await _messagingAvailable()) return;

    // The FID→user row is written by [registerInstallation], driven by auth
    // events (sign-in), not here: the FID stream is user-agnostic and fires at
    // FID birth, before any user is signed in. The FID rarely changes, but when
    // it does we re-register the current user (a no-op when signed out).
    _installations.onIdChange.listen((_) async {
      try {
        await syncPermissionAndRegistration();
      } catch (e, stack) {
        developer.log(
          'Installation id change registration failed',
          name: 'notifications',
          error: e,
          stackTrace: stack,
        );
      }
    });

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleTap(initial);
  }

  /// Registers the currently signed-in user on this install so the server can
  /// target it. Driven by auth state (sign-in / restored session), because the
  /// row maps a *user* to this device's FID and the FID stream knows nothing
  /// about who is logged in. A no-op when signed out; otherwise the idempotent
  /// upsert also repairs a row the server may have pruned after a 404. Errors
  /// are logged, never thrown.
  Future<void> registerInstallation() async {
    try {
      await syncPermissionAndRegistration();
    } catch (e, stack) {
      developer.log(
        'Installation registration failed',
        name: 'notifications',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Removes this install's notification registration on sign-out so the server
  /// stops targeting it immediately. Errors are logged but never thrown,
  /// sign-out must succeed regardless of cleanup status.
  ///
  /// Deletes only the DB row; it deliberately leaves the FCM registration and
  /// the Firebase installation intact. Deleting the installation would reset
  /// Crashlytics / Remote Config / A&B identity. The row delete alone stops the
  /// server targeting this user on this device.
  Future<void> deleteCurrentInstallation() async {
    try {
      final fid = await _installations.getId();
      await _installationRepository.delete(fid: fid);
      await _preferences.remove(_registeredKey);
    } catch (e, stack) {
      developer.log(
        'Failed to delete device installation on sign-out',
        name: 'notifications',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Returns the current permission/capability state without prompting.
  Future<NotificationPermissionState> permissionState() async {
    final available = await _messagingAvailable();
    if (!available) return NotificationPermissionState.unavailable;
    final settings = await _messaging.getNotificationSettings();
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    var hasRequestedPermission = false;
    if (isAndroid) {
      hasRequestedPermission =
          await _preferences.getBool(_permissionRequestedKey) == true;
    }
    return resolveNotificationPermissionState(
      authorizationStatus: settings.authorizationStatus,
      available: available,
      isAndroid: isAndroid,
      hasRequestedPermission: hasRequestedPermission,
    );
  }

  /// Requests permission in response to a deliberate user action.
  ///
  /// Callers must invoke this from an Enable button or equivalent contextual
  /// gesture. Initialization deliberately never calls it.
  Future<NotificationPermissionState> requestPermission() async {
    if (!await _messagingAvailable()) {
      return NotificationPermissionState.unavailable;
    }
    final result = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (isAndroid) {
      await _preferences.setBool(_permissionRequestedKey, true);
    }
    final state = resolveNotificationPermissionState(
      authorizationStatus: result.authorizationStatus,
      available: true,
      isAndroid: isAndroid,
      hasRequestedPermission: true,
    );
    if (state == NotificationPermissionState.enabled) {
      try {
        final fid = await _ensurePushRegistration();
        if (fid != null) await _register(fid: fid);
      } catch (error) {
        throw NotificationRegistrationException(error);
      }
    } else {
      await _unregisterIfRegistered();
    }
    return state;
  }

  /// Reconciles permission, the FCM subscription, and the server-side FID row.
  ///
  /// Called on startup, sign-in, FID changes, and app resume. This repairs a
  /// transient registration failure and notices permission changes made in
  /// Settings.
  Future<NotificationPermissionState> syncPermissionAndRegistration() async {
    final state = await permissionState();
    if (state == NotificationPermissionState.enabled) {
      try {
        final fid = await _ensurePushRegistration();
        if (fid != null) await _register(fid: fid);
      } catch (error, stackTrace) {
        developer.log(
          'Notification installation registration failed; will retry',
          name: 'notifications',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } else {
      await _unregisterIfRegistered();
    }
    return state;
  }

  Future<void> _createChannels() async {
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_yourTurnChannel);
    await android?.createNotificationChannel(_gameChannel);
    await android?.createNotificationChannel(_gameInvitesChannel);
    await android?.createNotificationChannel(_socialChannel);
    await android?.createNotificationChannel(_generalChannel);
  }

  /// Upserts the `(current user, FID)` row.
  ///
  /// Repeating this write is intentional: Firebase tells native clients to
  /// upload their FID on registration, but FlutterFire does not expose that
  /// callback yet. Startup/resume reconciliation therefore also repairs a row
  /// the sender pruned after a 404.
  Future<void> _register({String? fid}) async {
    final userId = _currentUserId();
    if (userId == null) return;
    final installationId = fid ?? await _installations.getId();
    final registered = '$userId:$installationId';
    await _upsertInstallation(installationId);
    await _preferences.setString(_registeredKey, registered);
  }

  Future<void> _upsertInstallation(String fid) =>
      _installationRepository.upsert(fid: fid);

  Future<void> _unregisterIfRegistered() async {
    if (await _preferences.getString(_registeredKey) == null) return;
    try {
      final fid = await _installations.getId();
      await _installationRepository.delete(fid: fid);
      await _preferences.remove(_registeredKey);
    } catch (error, stackTrace) {
      // Permission is already off. Keep the marker so a later resume retries
      // removing the stale server target, but do not fail app initialization.
      developer.log(
        'Notification registration cleanup failed; will retry',
        name: 'notifications',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _messagingAvailable() =>
      _availability ??= _checkMessagingAvailable();

  Future<bool> _checkMessagingAvailable() async {
    if (!kIsWeb) return true;
    try {
      return await _messaging.isSupported();
    } catch (error, stackTrace) {
      developer.log(
        'Web push is not supported in this browser',
        name: 'notifications',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Ensures this Firebase installation has a live FCM registration.
  ///
  /// The server targets the FID returned by Firebase Installations. The
  /// platform adapter calls Firebase's current registration API without
  /// creating or persisting a deprecated registration token.
  Future<String?> _ensurePushRegistration() =>
      _messagingRegistration.register(vapidKey: _vapidKey);

  void _showForegroundNotification(RemoteMessage message) {
    if (kIsWeb) return; // flutter_local_notifications has no web implementation
    final notification = message.notification;
    if (notification == null) return;
    // An unrecognised or missing category (a newer server than this build)
    // resolves to null and still shows, on the general channel, rather than
    // being dropped.
    final category = _NotificationCategory.fromString(
      message.data['category'] as String?,
    );
    if (category == null) {
      developer.log(
        'Unknown notification category: ${message.data['category']}: '
        'showing on the general channel',
        name: 'notifications',
      );
    }

    // Suppress "your turn" banners when the user is already on that game screen.
    if (category == _NotificationCategory.yourTurn) {
      final deepLink = message.data['deepLink'] as String?;
      final gameId = deepLink?.split('/').lastOrNull;
      if (gameId != null && gameId == _activeGameId()) return;
    }
    final channel = category == null ? _generalChannel : _channelFor(category);
    _localNotifications.show(
      id: _notificationId(message, category),
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: channel.importance == Importance.high
              ? Priority.high
              : Priority.defaultPriority,
          icon: '@drawable/ic_notification',
        ),
        iOS: DarwinNotificationDetails(
          // yourTurn breaks through Focus filters on iOS 15+.
          interruptionLevel: category == _NotificationCategory.yourTurn
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
      payload: message.data['deepLink'] as String?,
    );
  }

  void _handleTap(RemoteMessage message) {
    final deepLink = message.data['deepLink'] as String?;
    if (deepLink != null) _nav.add(deepLink);
  }

  AndroidNotificationChannel _channelFor(_NotificationCategory category) =>
      switch (category) {
        _NotificationCategory.yourTurn => _yourTurnChannel,
        _NotificationCategory.gameReady => _gameChannel,
        _NotificationCategory.gameFinished => _gameChannel,
        _NotificationCategory.gameInvite => _gameInvitesChannel,
        _NotificationCategory.friendRequest => _socialChannel,
        _NotificationCategory.friendAccepted => _socialChannel,
      };

  /// Game-scoped notifications (a turn, a ready, a finish) key off the deepLink
  /// which carries the gameId, so a later update for the same game replaces
  /// the earlier one. Everything else (invites, social, unknown) keys off
  /// messageId so events from different people/games stack independently.
  int _notificationId(RemoteMessage message, _NotificationCategory? category) {
    final gameScoped =
        category == _NotificationCategory.yourTurn ||
        category == _NotificationCategory.gameReady ||
        category == _NotificationCategory.gameFinished;
    final key = gameScoped
        ? (message.data['deepLink'] ?? message.messageId ?? '')
        : (message.messageId ?? message.data['deepLink'] ?? '');
    return key.hashCode & 0x7FFFFFFF;
  }
}
