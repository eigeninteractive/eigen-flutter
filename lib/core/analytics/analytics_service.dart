/// Typed analytics interface. Call sites are unaware of the backing
/// implementation (Firebase or no-op).
abstract class AnalyticsService {
  // ── Identity ───────────────────────────────────────────────────────────────

  /// Associates subsequent events with [userId].
  Future<void> identify(String userId);

  /// Clears the current identity (call on sign-out).
  Future<void> reset();

  // ── Events ─────────────────────────────────────────────────────────────────

  Future<void> gameCreated({
    required String gameId,
    required String access,
    required String timingMode,
    required bool rated,
  });

  Future<void> gameStarted({required String gameId, required int playerCount});

  Future<void> gameFinished({required String gameId});

  Future<void> forfeit();

  Future<void> joinByCode();

  Future<void> friendRequestSent();

  Future<void> friendAccepted();
}
