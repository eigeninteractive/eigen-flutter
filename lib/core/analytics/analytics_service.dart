/// Typed analytics interface. Call sites are unaware of the backing
/// implementation (Firebase or no-op).
abstract class AnalyticsService {
  // ── Identity ───────────────────────────────────────────────────────────────

  /// Associates subsequent events with [userId].
  Future<void> identify(String userId);

  /// Clears the current identity (call on sign-out).
  Future<void> reset();

  /// Tags the current user as a guest (anonymous) or registered account, so
  /// every other metric can be segmented by account type. Call whenever the
  /// session's account type is established or changes.
  Future<void> setAccountType({required bool isGuest});

  // ── Events ─────────────────────────────────────────────────────────────────

  /// A guest converted their anonymous session into a permanent account. The
  /// key conversion-funnel metric for guest auth.
  Future<void> guestUpgraded();

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

  /// A generated enum decoded a value this build does not understand.
  Future<void> wireEnumFallback({
    required String enumType,
    required String surface,
  });
}
