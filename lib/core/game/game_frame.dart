import 'package:eigen_engine/core/game/timing_context.dart';

/// A single observation snapshot of an active or finished game.
///
/// The per-event view of everything that *changes* as a game progresses: the
/// parsed observation, the optimistic-lock version, the players whose turn is
/// active, and the turn timing. Rebuilt on every Realtime observation event.
///
/// The engine is deliberately not part of the frame. It is created once from
/// the immutable game config and lives for the whole game, so it is a separate,
/// longer-lived concern carried alongside the frame (see `gameEngineProvider`
/// and [GameContentContext.engine]) rather than re-bundled into every snapshot.
class GameFrame {
  const GameFrame({
    required this.observation,
    required this.pendingPlayers,
    required this.version,
    required this.timing,
  });

  /// Game-specific parsed observation. Null until the first observation event
  /// arrives after the game becomes active.
  final Object? observation;

  /// Current pending players from the infra observation row.
  final List<int> pendingPlayers;

  /// Mirrored from [game_states.version] via the observation row. Passed back
  /// to `engine_commit_action` as the optimistic lock key.
  final int version;

  /// Timing metadata for the current turn, derived from the observation row.
  ///
  /// All fields may be null depending on the game's timing configuration.
  final TimingContext timing;
}
