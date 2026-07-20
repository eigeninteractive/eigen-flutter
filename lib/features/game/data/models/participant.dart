import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:eigen_flutter/core/game/participant_type.dart';

part 'participant.freezed.dart';
part 'participant.g.dart';

/// A participant in a game.
///
/// Represents a player (human or bot) in a game with their seat index.
@freezed
abstract class Participant with _$Participant {
  const factory Participant({
    required String id,
    required String gameId,
    String? userId,
    String? botId,
    required int playerIndex,
    @JsonKey(unknownEnumValue: ParticipantType.unknown)
    required ParticipantType type,
    required DateTime createdAt,
  }) = _Participant;

  factory Participant.fromJson(Map<String, dynamic> json) =>
      _$ParticipantFromJson(json);
}
