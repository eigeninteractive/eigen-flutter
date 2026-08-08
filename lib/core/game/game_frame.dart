import 'package:eigen_flutter/core/game/timing_context.dart';

/// A single observation snapshot of an active or finished game.
///
/// The per-event view of everything that *changes* as a game progresses: the
/// parsed observation, the optimistic-lock version, the players whose turn is
/// active, and the turn timing. Rebuilt on every frame the game socket emits.
///
/// The parsed game config is deliberately not part of the frame. It is parsed
/// once from the immutable game config and lives for the whole game, so it is
/// a separate, longer-lived concern carried alongside the frame (see
/// `gameConfigProvider` and [GameContentContext.config]) rather than
/// re-bundled into every snapshot.
///
/// Frames arrive as an ordered, gap-recovered stream (observations are
/// append-only server-side, and a reconnect replays whatever versions the
/// socket missed), so a game may animate the transition between consecutive frames
/// and trust that it sees every one, falling back to a snap only after a
/// cold (re)load, where no predecessor was rendered.
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

  /// The game state's version, carried on the observation. Passed back when
  /// submitting an action as the optimistic lock key.
  final int version;

  /// Timing metadata for the current turn, derived from the observation row.
  ///
  /// All fields may be null depending on the game's timing configuration.
  final TimingContext timing;
}
