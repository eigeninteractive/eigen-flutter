import 'package:checks/checks.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/core/game/game_status.dart';
import 'package:eigen_engine/core/game/participant_type.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
import 'package:eigen_engine/features/game/data/models/participant.dart';
import 'package:eigen_engine/features/social/data/models/friendship.dart';
import 'package:flutter_test/flutter_test.dart';

/// Forward-compatibility: a build must tolerate JSON from a newer backend —
/// unknown enum values decode to a sentinel, unknown fields are ignored, and
/// newly-added fields fall back to their `@Default`.
void main() {
  const iso = '2026-06-15T10:30:00.000Z';

  test('Game tolerates unknown enums, extra fields, and missing schema', () {
    final game = Game.fromJson(<String, Object?>{
      'id': 'g',
      'status': 'time_warp', // unknown GameStatus
      'access': 'galaxy', // unknown GameAccess
      'min_players': 2,
      'max_players': 2,
      'config': <String, Object?>{},
      'schema_version': 1,
      'rated': false,
      'created_at': iso,
      'updated_at': iso,
      'a_future_field': 'ignored', // unknown field must be ignored
    });

    check(game.status).equals(GameStatus.unknown);
    check(game.access).equals(GameAccess.unknown);
    check(game.schemaVersion).equals(1);
  });

  test('GameOutcome tolerates an unknown result', () {
    final outcome = GameOutcome.fromJson(<String, Object?>{
      'game_id': 'g',
      'player_index': 0,
      'result': 'transcended',
      'placement': 1,
      'team_index': 0,
    });
    check(outcome.result).equals(OutcomeResult.unknown);
  });

  test('Friendship tolerates an unknown status', () {
    final friendship = Friendship.fromJson(<String, Object?>{
      'user_id': 'u',
      'friend_id': 'f',
      'status': 'frenemy',
      'initiated_by': 'u',
      'created_at': iso,
      'updated_at': iso,
    });
    check(friendship.status).equals(RelationshipStatus.unknown);
  });

  test('Participant tolerates an unknown type', () {
    final participant = Participant.fromJson(<String, Object?>{
      'id': 'p',
      'game_id': 'g',
      'player_index': 0,
      'type': 'alien',
      'created_at': iso,
    });
    check(participant.type).equals(ParticipantType.unknown);
  });
}
