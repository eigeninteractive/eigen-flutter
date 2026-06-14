import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Android notification channels ────────────────────────────────────────────
// Each channel appears as an independent toggle in Android system settings,
// giving users per-category control without any in-app preference tracking.

const _yourTurnChannel = AndroidNotificationChannel(
  'your_turn',
  'Your Turn',
  description: 'Alerts when it\'s your move in an active game.',
  importance: Importance.high,
);

const _gameInvitesChannel = AndroidNotificationChannel(
  'game_invites',
  'Game Invites',
  description: 'Alerts when a friend creates a game for you.',
  importance: Importance.defaultImportance,
);

const _socialChannel = AndroidNotificationChannel(
  'social_notifications',
  'Social & Friends',
  description: 'Friend requests and social updates.',
  importance: Importance.low,
);

// ── Notification category ─────────────────────────────────────────────────────

enum _NotificationCategory {
  yourTurn,
  gameInvite,
  friendRequest;

  /// Parses the `category` field from the FCM data payload.
  /// Throws [ArgumentError] for unknown or missing values — every notification
  /// must declare its category explicitly.
  static _NotificationCategory fromString(String? value) => switch (value) {
    'your_turn' => yourTurn,
    'game_invite' => gameInvite,
    'friend_request' => friendRequest,
    _ => throw ArgumentError.value(value, 'category'),
  };
}

// ── Service ───────────────────────────────────────────────────────────────────

/// FCM push notification service using Firebase Cloud Messaging.
class FirebaseNotificationService {
  FirebaseNotificationService({
    required FirebaseMessaging messaging,
    required SupabaseClient supabase,
    required FlutterLocalNotificationsPlugin localNotifications,
    required String? Function() activeGameId,
    String? vapidKey,
  }) : _messaging = messaging,
       _supabase = supabase,
       _localNotifications = localNotifications,
       _activeGameId = activeGameId,
       _vapidKey = vapidKey;

  final FirebaseMessaging _messaging;
  final SupabaseClient _supabase;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final String? Function() _activeGameId;

  /// VAPID key for FCM Web Push, injected from [EngineConfig]; null on mobile.
  final String? _vapidKey;

  final StreamController<String> _nav = StreamController<String>.broadcast();
  bool _initialized = false;

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

    final token = await _messaging.getToken(
      vapidKey: kIsWeb ? _vapidKey : null,
    );
    if (token != null) await _upsertToken(token);
    _messaging.onTokenRefresh.listen((t) async {
      try {
        await _upsertToken(t);
      } catch (e, stack) {
        developer.log(
          'Token refresh upsert failed',
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

  /// Deletes the current device token on sign-out so this install stops
  /// receiving notifications immediately. Errors are logged but never thrown —
  /// sign-out must succeed regardless of token cleanup status.
  Future<void> deleteCurrentToken() async {
    try {
      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? _vapidKey : null,
      );
      if (token == null) return;
      await _supabase.rpc('delete_device_token', params: {'p_token': token});
      await _messaging.deleteToken();
    } catch (e, stack) {
      developer.log(
        'Failed to delete device token on sign-out',
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
    await android?.createNotificationChannel(_gameInvitesChannel);
    await android?.createNotificationChannel(_socialChannel);
  }

  Future<void> _upsertToken(String token) async {
    final platform = kIsWeb
        ? 'web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
            TargetPlatform.android => 'android',
            _ => throw UnsupportedError(
              'Push notifications not supported on $defaultTargetPlatform',
            ),
          };
    await _supabase.rpc(
      'upsert_device_token',
      params: {'p_token': token, 'p_platform': platform},
    );
  }

  void _showForegroundNotification(RemoteMessage message) {
    if (kIsWeb) return; // flutter_local_notifications has no web implementation
    final notification = message.notification;
    if (notification == null) return;
    final _NotificationCategory category;
    try {
      category = _NotificationCategory.fromString(
        message.data['category'] as String?,
      );
    } catch (e, stack) {
      developer.log(
        'Unknown notification category: ${message.data['category']}',
        name: 'notifications',
        error: e,
        stackTrace: stack,
      );
      return;
    }

    // Suppress "your turn" banners when the user is already on that game screen.
    if (category == _NotificationCategory.yourTurn) {
      final deepLink = message.data['deep_link'] as String?;
      final gameId = deepLink?.split('/').lastOrNull;
      if (gameId != null && gameId == _activeGameId()) return;
    }
    final channel = _channelFor(category);
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
      payload: message.data['deep_link'] as String?,
    );
  }

  void _handleTap(RemoteMessage message) {
    final deepLink = message.data['deep_link'] as String?;
    if (deepLink != null) _nav.add(deepLink);
  }

  AndroidNotificationChannel _channelFor(_NotificationCategory category) =>
      switch (category) {
        _NotificationCategory.yourTurn => _yourTurnChannel,
        _NotificationCategory.gameInvite => _gameInvitesChannel,
        _NotificationCategory.friendRequest => _socialChannel,
      };

  /// yourTurn uses deep_link (contains gameId) so a second notification for
  /// the same game replaces the first. Other categories use messageId so
  /// notifications from different people stack independently.
  int _notificationId(RemoteMessage message, _NotificationCategory category) {
    final key = category == _NotificationCategory.yourTurn
        ? (message.data['deep_link'] ?? message.messageId ?? '')
        : (message.messageId ?? message.data['deep_link'] ?? '');
    return key.hashCode & 0x7FFFFFFF;
  }
}
