import 'package:checks/checks.dart';
import 'package:eigen_engine/features/game/data/models/participant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Participant round-trips with a ParticipantType enum', () {
    final json = <String, Object?>{
      'id': 'pa1',
      'game_id': 'g1',
      'user_id': 'u1',
      'bot_id': null,
      'player_index': 0,
      'type': 'human',
      'created_at': '2026-06-15T10:30:00.000Z',
    };
    check(Participant.fromJson(json).toJson()).deepEquals(json);
  });
}
