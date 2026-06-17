import 'package:freezed_annotation/freezed_annotation.dart';

part 'game_outcome.freezed.dart';
part 'game_outcome.g.dart';

/// Result for one participant in a completed game.
///
/// [unknown] is a forward-compatibility sentinel for values a newer server may
/// introduce. See `docs/backward-compatibility.md`.
enum OutcomeResult { win, loss, draw, eliminated, unknown }

/// One participant's outcome from the [game_outcomes] table.
///
/// Written server-side by [submit_action] when the game ends. One row per
/// participant per completed game. Supports multi-winner games (team wins),
/// score-based ELO, and placement-based ELO for N-player games.
@freezed
abstract class GameOutcome with _$GameOutcome {
  const factory GameOutcome({
    required String gameId,
    required int playerIndex,
    String? userId,
    String? botId,
    @JsonKey(unknownEnumValue: OutcomeResult.unknown)
    required OutcomeResult result,
    double? score,
    required int placement,
    required int teamIndex,
  }) = _GameOutcome;

  factory GameOutcome.fromJson(Map<String, dynamic> json) =>
      _$GameOutcomeFromJson(json);
}
