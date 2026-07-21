import 'package:eigen_flutter/core/api/server_clock.dart';

/// Timing data passed to [GameRules.buildContent] for every active game.
///
/// Fields are null when not applicable to the game's timing mode - check
/// before using. Use [TurnTimerBuilder] or [PlayerTimerBuilder] from
/// `timer_builders.dart` to render live countdowns from these values.
///
/// Index scheme: all lists are 0-based player indices, consistent with
/// [GameFrame.pendingPlayers].
class TimingContext {
  const TimingContext({
    required this.clock,
    this.playerTimes,
    this.deadline,
    this.windowMillis,
  });

  /// Server time. Deadlines are absolute server timestamps, so every countdown
  /// measures against this rather than the device clock - a device whose clock
  /// is off would otherwise disagree with when the turn actually expires.
  final ServerClock clock;

  /// Remaining budget in milliseconds per player, 0-indexed.
  ///
  /// Non-null only in budget (accumulated clock) mode. These are the values as
  /// of this frame: the *running* player's bank is draining and should be read
  /// from [remaining] instead, while every other player's is static.
  final List<int>? playerTimes;

  /// Absolute deadline for the current turn as epoch milliseconds on the
  /// server. Non-null for any timed game - per-action mode, budget mode, or a
  /// hook-override deadline.
  ///
  /// This is the same instant the server's own expiry alarm fires on, so a
  /// countdown derived from it cannot disagree with when the turn really dies.
  /// The server additionally allows a grace period, deliberately not reflected
  /// here: the client shows the true deadline and lets the server be lenient.
  final int? deadline;

  /// How long the current turn was when it began, in milliseconds.
  ///
  /// Not on the wire - the server sends only the deadline, since that is the
  /// one value it is authoritative about. Derived instead from the game's
  /// configured turn length, or in budget mode from the acting seat's bank,
  /// which *is* the window. Used only to size the soft-deadline margin, so
  /// being approximate is fine and being absent is safe.
  final int? windowMillis;

  /// Whether this game is timed at all.
  bool get isTimed => deadline != null;

  /// The deadline on the device clock, for widgets that tick against
  /// `DateTime.now()`. Null when untimed.
  DateTime? get deviceDeadline {
    final at = deadline;
    return at == null ? null : clock.deviceTimeFor(at);
  }

  /// Time left on the current turn, or null when untimed.
  ///
  /// Clamped at zero once the deadline passes. In budget mode this is the
  /// running player's remaining bank - budget mode permits only one pending
  /// seat, so the turn deadline and that seat's bank are the same quantity.
  Duration? get remaining {
    final at = deadline;
    return at == null ? null : clock.remainingUntil(at);
  }

  /// [player]'s remaining bank, live for whoever is on the clock.
  ///
  /// Returns null outside budget mode. For the player currently acting this
  /// tracks down in real time via [remaining]; for everyone else it is the
  /// static value from this frame, since only one bank drains at a time.
  Duration? bankFor(int player, {required List<int> pendingPlayers}) {
    final times = playerTimes;
    if (times == null || player >= times.length) return null;
    if (pendingPlayers.length == 1 && pendingPlayers.first == player) {
      return remaining ?? Duration(milliseconds: times[player]);
    }
    return Duration(milliseconds: times[player]);
  }
}
