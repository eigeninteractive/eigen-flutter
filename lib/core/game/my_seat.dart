/// The current user's place in a game, as seen by [GameRules.buildContent].
///
/// A participant is [Seated] at a concrete seat index; a non-participant
/// replaying a public game is a [Viewer] with no seat. Modelling the two as a
/// sealed type (rather than an `int` with a `-1` sentinel) makes "a viewer with
/// a seat" and "a participant without one" unrepresentable, and lets rendering
/// code exhaustively `switch` on the distinction.
library;

/// A sealed union of the two ways the current user relates to a game.
///
/// `switch` on it to handle both cases, or read [indexOrNull] for the common
/// "is it my turn / is this my seat" checks where a viewer simply never
/// matches.
sealed class MySeat {
  const MySeat();

  /// The seat index when [Seated], or null for a [Viewer].
  ///
  /// A convenience for reads that treat "no seat" as "never me", e.g.
  /// `pendingPlayers.contains(mySeat.indexOrNull)` is `false` for a viewer.
  /// Prefer an exhaustive `switch` when the viewer case needs distinct
  /// handling.
  int? get indexOrNull => switch (this) {
    Seated(:final index) => index,
    Viewer() => null,
  };
}

/// The current user holds seat [index] in the game (a participant).
final class Seated extends MySeat {
  const Seated(this.index);

  /// The user's 0-based seat index.
  final int index;
}

/// The current user has no seat: a non-participant viewing a replay.
final class Viewer extends MySeat {
  const Viewer();
}
