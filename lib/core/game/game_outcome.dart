import 'package:freezed_annotation/freezed_annotation.dart';

part 'game_outcome.freezed.dart';
part 'game_outcome.g.dart';

/// Result for one participant in a completed game.
enum OutcomeResult { win, loss, draw, eliminated }

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
    required OutcomeResult result,
    double? score,
    required int placement,
    required int teamIndex,
  }) = _GameOutcome;

  factory GameOutcome.fromJson(Map<String, dynamic> json) =>
      _$GameOutcomeFromJson(json);
}
