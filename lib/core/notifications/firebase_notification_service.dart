import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

/// Catch-all for a category this build does not recognise — a newer server
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

  /// Parses the `category` field from the FCM data payload — the exact set the
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

// ── Service ───────────────────────────────────────────────────────────────────

/// FCM push notification service using Firebase Cloud Messaging.
class FirebaseNotificationService {
  FirebaseNotificationService({
    required FirebaseMessaging messaging,
    required FirebaseInstallations installations,
    required DeviceInstallationRepository installationRepository,
    required FlutterLocalNotificationsPlugin localNotifications,
    required String? Function() activeGameId,
    required String? Function() currentUserId,
    String? vapidKey,
  }) : _messaging = messaging,
       _installations = installations,
       _installationRepository = installationRepository,
       _localNotifications = localNotifications,
       _activeGameId = activeGameId,
       _currentUserId = currentUserId,
       _vapidKey = vapidKey;

  final FirebaseMessaging _messaging;
  final FirebaseInstallations _installations;
  final DeviceInstallationRepository _installationRepository;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final String? Function() _activeGameId;

  /// Reads the signed-in user's id at call time (null when signed out), so
  /// registration follows the live session without holding an auth handle.
  final String? Function() _currentUserId;

  /// VAPID key for FCM Web Push, injected from [EngineConfig]; null on mobile.
  final String? _vapidKey;

  final StreamController<String> _nav = StreamController<String>.broadcast();
  bool _initialized = false;

  /// SharedPreferences key holding the last-registered `userId:fid`, used to
  /// skip redundant upserts on app start.
  static const _registeredKey = 'notifications_registered_installation';

  Stream<String> get navigationStream => _nav.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

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
        // Permission is requested exclusively via FirebaseMessaging.requestPermission(),
        // guarded by a SharedPreferences key. Setting all request flags to false
        // prevents flutter_local_notifications from issuing a duplicate iOS dialog.
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

    // Show the OS permission dialog on first launch only. After that the user
    // controls permissions via system Settings — we never re-prompt
    // automatically. The Settings screen calls requestPermission() directly.
    final prefs = await SharedPreferences.getInstance();
    const permKey = 'notifications_permission_requested';
    if (prefs.getBool(permKey) != true) {
      await prefs.setBool(permKey, true);
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    }

    // FCM v1 targets the Firebase Installation ID (FID), not the registration
    // token. We still call getToken() to force this install to register with
    // FCM — a FID only resolves to a live registration once the device has one —
    // but its result is no longer stored. On web the token drives service-worker
    // registration, so the vapidKey call is required there regardless.
    await _messaging.getToken(vapidKey: kIsWeb ? _vapidKey : null);

    // The FID→user row is written by [registerInstallation], driven by auth
    // events (sign-in), not here: the FID stream is user-agnostic and fires at
    // FID birth, before any user is signed in. The FID rarely changes, but when
    // it does we re-register the current user (a no-op when signed out).
    _installations.onIdChange.listen((_) async {
      try {
        await _register();
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
  /// about who is logged in. A no-op when signed out or when the current
  /// (user, FID) pair is already registered (tracked in [SharedPreferences]),
  /// so a returning user writes nothing. Errors are logged, never thrown.
  Future<void> registerInstallation() async {
    try {
      await _register();
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
  /// stops targeting it immediately. Errors are logged but never thrown —
  /// sign-out must succeed regardless of cleanup status.
  ///
  /// Deletes only the DB row; it deliberately leaves the FCM registration and
  /// the Firebase installation intact. Dropping the FCM token here would not be
  /// re-established until the next process start (registration runs once in
  /// [initialize]), breaking same-session re-sign-in; and deleting the
  /// installation would reset Crashlytics / Remote Config / A&B identity. The
  /// row delete alone stops the server targeting this user on this device.
  Future<void> deleteCurrentInstallation() async {
    try {
      final fid = await _installations.getId();
      await _installationRepository.delete(fid: fid);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_registeredKey);
    } catch (e, stack) {
      developer.log(
        'Failed to delete device installation on sign-out',
        name: 'notifications',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<AuthorizationStatus> requestPermission() async {
    final result = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return result.authorizationStatus;
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

  /// Upserts the `(current user, FID)` row, skipping the write when that exact
  /// pair is already the last one registered on this install. The guard makes a
  /// returning user's app start a no-op rather than a redundant write; a new
  /// sign-in (user changes) or a FID rotation (FID changes) both miss the guard
  /// and re-register.
  Future<void> _register() async {
    final userId = _currentUserId();
    if (userId == null) return;
    final fid = await _installations.getId();
    final prefs = await SharedPreferences.getInstance();
    final registered = '$userId:$fid';
    if (prefs.getString(_registeredKey) == registered) return;
    await _upsertInstallation(fid);
    await prefs.setString(_registeredKey, registered);
  }

  Future<void> _upsertInstallation(String fid) =>
      _installationRepository.upsert(fid: fid);

  void _showForegroundNotification(RemoteMessage message) {
    if (kIsWeb) return; // flutter_local_notifications has no web implementation
    final notification = message.notification;
    if (notification == null) return;
    // An unrecognised or missing category (a newer server than this build)
    // resolves to null and still shows — on the general channel — rather than
    // being dropped.
    final category = _NotificationCategory.fromString(
      message.data['category'] as String?,
    );
    if (category == null) {
      developer.log(
        'Unknown notification category: ${message.data['category']} — '
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
  /// — which carries the gameId — so a later update for the same game replaces
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
