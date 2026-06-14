import 'package:freezed_annotation/freezed_annotation.dart';

part 'observation.freezed.dart';
part 'observation.g.dart';

/// A player's observation of a game state.
///
/// Infra-level row. [data] is the opaque game-specific payload.
/// [pendingPlayers] mirrors the server's canonical set of indices allowed
/// to act. Callers derive "is my turn" as
/// `pendingPlayers.contains(myPlayerIndex)` — participant index is known
/// in the caller's context and doesn't need to be denormalized here.
@freezed
abstract class Observation with _$Observation {
  const factory Observation({
    required String gameId,
    required String userId,
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
