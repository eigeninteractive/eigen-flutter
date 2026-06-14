/// Timing data passed to [GameModule.buildContent] for every active game.
///
/// Fields are null when not applicable to the game's timing mode — check
/// before using. Use [TurnTimerBuilder] or [PlayerTimerBuilder] from
/// `timer_builders.dart` to render live countdowns from these values.
///
/// Index scheme: all lists are 0-based player indices, consistent with
/// [GameFrame.pendingPlayers].
class TimingContext {
  const TimingContext({
    this.playerTimes,
    this.turnStartedAt,
    this.turnDeadline,
  });

  /// Remaining budget in milliseconds per player, 0-indexed.
  ///
  /// Non-null only in budget (accumulated clock) mode. Use with
  /// [PlayerTimerBuilder] to render a live draining clock for any player:
  /// pass [playerIndex] for the player you want to display.
  final List<int>? playerTimes;

  /// Server timestamp of when the current turn began.
  ///
  /// Combined with [playerTimes] by [PlayerTimerBuilder] to animate the active
  /// player's live drain without polling. Null for non-budget games.
  final DateTime? turnStartedAt;

  /// Absolute deadline for the current turn. Non-null for any timed game
  /// (per-action mode, budget mode, or a hook-override deadline).
  ///
  /// Use with [TurnTimerBuilder] to render a shared countdown. In budget mode
  /// prefer [playerTimes] + [PlayerTimerBuilder] for per-player display; use
  /// this only if you want a single unified "time left this turn" indicator.
  final DateTime? turnDeadline;
}
