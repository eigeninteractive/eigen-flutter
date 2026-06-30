import 'package:freezed_annotation/freezed_annotation.dart';

part 'observation.freezed.dart';
part 'observation.g.dart';

/// A player's observation of a game state.
///
/// Infra-level row, one per participant (human or bot), keyed by
/// `(gameId, playerIndex)`. [data] is the opaque game-specific payload.
/// [pendingPlayers] mirrors the server's canonical set of indices allowed
/// to act; callers derive "is my turn" as `pendingPlayers.contains(playerIndex)`.
///
/// Exactly one of [userId] / [botId] is set: a human's own row carries [userId]
/// (and RLS hides everyone else's), while a bot seat's row carries [botId] and is
/// returned only via `app_local_bot_observation` for the sole human of a solo game.
@freezed
abstract class Observation with _$Observation {
  const factory Observation({
    required String gameId,

    /// The seat this observation belongs to.
    required int playerIndex,

    /// Set for a human's row; null for a bot seat's row.
    String? userId,

    /// Set for a bot seat's row; null for a human's row.
    String? botId,
    required Map<String, dynamic> data,
    required List<int> pendingPlayers,
    required int version,

    /// Mirrors [game_states.turn_deadline]. Null for untimed games or after
    /// game end. Clients use this to display countdown timers.
    DateTime? turnDeadline,

    /// Mirrors [game_states.player_times]. Null for games without a budget
    /// (accumulated) clock. Entry at index i is player i's remaining ms.
    List<int>? playerTimes,

    /// Mirrors [game_states.turn_started_at]. Null for untimed games.
    /// Combined with [playerTimes] to animate the active player's live
    /// countdown without polling.
    DateTime? turnStartedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Observation;

  factory Observation.fromJson(Map<String, dynamic> json) =>
      _$ObservationFromJson(json);
}
