import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:eigen_flutter/core/analytics/analytics_service.dart';

/// Firebase Analytics implementation of [AnalyticsService].
class FirebaseAnalyticsService implements AnalyticsService {
  FirebaseAnalyticsService(this._analytics);

  final FirebaseAnalytics _analytics;

  @override
  Future<void> identify(String userId) => _analytics.setUserId(id: userId);

  @override
  Future<void> reset() => _analytics.setUserId(id: null);

  @override
  Future<void> setAccountType({required bool isGuest}) =>
      _analytics.setUserProperty(
        name: 'account_type',
        value: isGuest ? 'guest' : 'registered',
      );

  @override
  Future<void> guestUpgraded() => _analytics.logEvent(name: 'guest_upgraded');

  @override
  Future<void> gameCreated({
    required String gameId,
    required String access,
    required String timingMode,
    required bool rated,
  }) => _analytics.logEvent(
    name: 'game_created',
    parameters: {
      'game_id': gameId,
      'access': access,
      'timing_mode': timingMode,
      'rated': rated ? 1 : 0,
    },
  );

  @override
  Future<void> gameStarted({
    required String gameId,
    required int playerCount,
  }) => _analytics.logEvent(
    name: 'game_started',
    parameters: {'game_id': gameId, 'player_count': playerCount},
  );

  @override
  Future<void> gameFinished({required String gameId}) => _analytics.logEvent(
    name: 'game_finished',
    parameters: {'game_id': gameId},
  );

  @override
  Future<void> forfeit() => _analytics.logEvent(name: 'forfeit');

  @override
  Future<void> joinByCode() => _analytics.logEvent(name: 'join_by_code');

  @override
  Future<void> friendRequestSent() =>
      _analytics.logEvent(name: 'friend_request_sent');

  @override
  Future<void> friendAccepted() => _analytics.logEvent(name: 'friend_accepted');

  @override
  Future<void> wireEnumFallback({
    required String enumType,
    required String surface,
  }) => _analytics.logEvent(
    name: 'wire_enum_fallback',
    parameters: {'enum_type': enumType, 'surface': surface},
  );
}
