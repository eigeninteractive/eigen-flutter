import 'package:eigen_engine/core/game/game_player.dart';

/// Player identity data passed to [GameRules.buildContent].
///
/// Maps player indices (0-based) to their resolved [GamePlayer] data.
/// The game implementor can use this to render opponent names, avatars,
/// or custom player labels.
///
/// The provider guarantees every participant has a resolved entry before
/// constructing this context, so [operator[]] is non-nullable.
class PlayersContext {
  const PlayersContext({required this.players, required this.myPlayerIndex});

  /// Resolved players keyed by player index.
  final Map<int, GamePlayer> players;

  /// The current user's player index in this game, or -1 if spectating.
  final int myPlayerIndex;

  /// Returns the [GamePlayer] for [playerIndex].
  ///
  /// Always returns data — the provider guarantees completeness.
  GamePlayer operator [](int playerIndex) => players[playerIndex]!;

  /// Convenience accessor for the current user's [GamePlayer].
  GamePlayer get me => this[myPlayerIndex];
}
