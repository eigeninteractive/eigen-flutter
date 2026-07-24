/// The v1 payload types — the Dart mirror of the TypeScript unit's Zod
/// `schemas` in `eigen-server/examples/rps/src/rules/v1.ts`.
///
/// Freezed plus `json_serializable`, which is what a real game uses and what
/// the [GameRules] codec is designed around. Two of Freezed's guarantees are
/// load-bearing here rather than merely convenient:
///
/// - **Value equality, including collections.** The twin fixture runner
///   compares observations with `==`, so a type without it asserts nothing at
///   all. Freezed compares `List` fields with deep equality, which matters
///   because every field on the board is a list.
/// - **Immutability.** An observation is a snapshot of one frame. Nothing on
///   the client is allowed to edit it into the next one — the next one arrives
///   from the server.
///
/// Regenerate after any edit:
///
/// ```bash
/// dart run build_runner build --delete-conflicting-outputs
/// ```
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

/// A throw. The wire representation is the lowercase name, matching the TS
/// `moveSchema` enum members exactly.
///
/// The `@JsonValue` annotations pin the wire strings so a Dart rename cannot
/// silently change the payload. Decoding is **strict**: there is no
/// `unknownEnumValue`, so a member added server-side throws here rather than
/// rendering an empty board. That is the same closed-set policy the generated
/// `eigen_api` enums use, and it is what makes adding an enum member a
/// breaking change you find in CI.
@JsonEnum()
enum RpsMove {
  @JsonValue('rock')
  rock,
  @JsonValue('paper')
  paper,
  @JsonValue('scissors')
  scissors;

  /// Whether this move beats [other] — the Dart transcription of the TS
  /// `beats()` helper. Used for rendering the reveal, never for scoring: the
  /// server already decided the winner and put it in [RpsRound.winner].
  bool beats(RpsMove other) => switch (this) {
    RpsMove.rock => other == RpsMove.scissors,
    RpsMove.paper => other == RpsMove.rock,
    RpsMove.scissors => other == RpsMove.paper,
  };
}

/// The last resolved round — the reveal both clients animate.
@freezed
abstract class RpsRound with _$RpsRound {
  const factory RpsRound({
    /// Both seats' throws, indexed by seat.
    required List<RpsMove> moves,

    /// The winning seat, or null when the round was drawn.
    required int? winner,
  }) = _RpsRound;

  factory RpsRound.fromJson(Map<String, dynamic> json) =>
      _$RpsRoundFromJson(json);
}

/// One seat's view of the match — the shape the TS `computeObservation` hook
/// projects, and the *only* game payload this side ever parses.
///
/// It is deliberately not the server's state. Two fields differ by audience,
/// because `computeObservation` emits two different shapes:
///
/// - **live play** sets [yourMove] (your own commit, echoed back) and omits
///   `commits`, so the opponent's throw is simply not in the bytes that reach
///   this device. There is no hidden field to accidentally render.
/// - **replay and public viewing** set [commits] instead and leave [yourMove]
///   null, because the match is over and there is nothing left to hide.
///
/// A codec that handles both is the whole of what hidden information costs on
/// the client. Both audience-specific fields are optional rather than
/// `required` for exactly that reason — neither shape carries the other's.
@freezed
abstract class RpsObservation with _$RpsObservation {
  const RpsObservation._();

  const factory RpsObservation({
    /// 1-based; increments when a resolved round leaves the match undecided.
    required int round,

    /// Rounds won, indexed by seat.
    required List<int> wins,

    /// The previous round's reveal, or null before the first round resolves.
    required RpsRound? lastRound,

    /// This seat's own commit for the current round, or null if it has not
    /// thrown yet. Live play only.
    RpsMove? yourMove,

    /// Both seats' commits for the current round. Replay and public viewing
    /// only — null during live play, which is exactly the point.
    List<RpsMove?>? commits,
  }) = _RpsObservation;

  factory RpsObservation.fromJson(Map<String, dynamic> json) =>
      _$RpsObservationFromJson(json);

  /// Whether this seat has already committed this round, under either shape.
  bool committedBy(int seat) =>
      commits != null ? commits![seat] != null : yourMove != null;
}

/// A throw, submitted to the server.
@freezed
abstract class RpsAction with _$RpsAction {
  const factory RpsAction({required RpsMove move}) = _RpsAction;

  factory RpsAction.fromJson(Map<String, dynamic> json) =>
      _$RpsActionFromJson(json);
}

/// The settings chosen when the match was created — immutable for its whole
/// life, which is why the framework parses it once instead of per frame.
@freezed
abstract class RpsConfig with _$RpsConfig {
  const factory RpsConfig({
    /// First to this many round wins takes the match.
    required int targetWins,
  }) = _RpsConfig;

  factory RpsConfig.fromJson(Map<String, dynamic> json) =>
      _$RpsConfigFromJson(json);
}
