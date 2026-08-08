import 'package:eigen_flutter/core/game/game_player.dart';
import 'package:eigen_flutter/core/game/my_seat.dart';

/// Player identity data passed to [GameRules.buildContent].
///
/// Maps player indices (0-based) to their resolved [GamePlayer] data.
/// The game implementor can use this to render opponent names, avatars,
/// or custom player labels.
///
/// The provider guarantees every participant has a resolved entry before
/// constructing this context, so [operator[]] is non-nullable.
class PlayersContext {
  const PlayersContext({required this.players, required this.mySeat});

  /// Resolved players keyed by player index.
  final Map<int, GamePlayer> players;

  /// The current user's place in this game: [Seated] at an index for a
  /// participant, or a [Viewer] for a non-participant replaying a public game.
  final MySeat mySeat;

  /// Returns the [GamePlayer] for [playerIndex].
  ///
  /// Always returns data; the provider guarantees completeness.
  GamePlayer operator [](int playerIndex) => players[playerIndex]!;

  /// The current user's [GamePlayer], or null when a [Viewer] (no seat).
  GamePlayer? get me => switch (mySeat) {
    Seated(:final index) => players[index],
    Viewer() => null,
  };
}
