import 'package:checks/checks.dart';
import 'package:eigen_engine/features/game/data/models/observation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Observation round-trips with timing fields present', () {
    final json = <String, Object?>{
      'game_id': 'g1',
      'player_index': 1,
      'user_id': 'u1',
      'bot_id': null,
      'data': {
        'cells': [null, 1],
      },
      'pending_players': [0, 1],
      'version': 3,
      'turn_deadline': '2026-06-15T10:35:00.000Z',
      'player_times': [60000, 55000],
      'turn_started_at': '2026-06-15T10:30:00.000Z',
      'created_at': '2026-06-15T10:30:00.000Z',
    };
    check(Observation.fromJson(json).toJson()).deepEquals(json);
  });

  test('Observation round-trips an untimed game (null timing fields)', () {
    final json = <String, Object?>{
      'game_id': 'g1',
      'player_index': 0,
      'user_id': 'u1',
      'bot_id': null,
      'data': <String, Object?>{},
      'pending_players': <int>[],
      'version': 1,
      'turn_deadline': null,
      'player_times': null,
      'turn_started_at': null,
      'created_at': '2026-06-15T10:30:00.000Z',
    };
    check(Observation.fromJson(json).toJson()).deepEquals(json);
  });

  test('Observation round-trips a bot seat row (null user_id, bot_id set)', () {
    final json = <String, Object?>{
      'game_id': 'g1',
      'player_index': 2,
      'user_id': null,
      'bot_id': 'b1',
      'data': {
        'cells': [null, 1],
      },
      'pending_players': [2],
      'version': 5,
      'turn_deadline': null,
      'player_times': null,
      'turn_started_at': null,
      'created_at': '2026-06-15T10:30:00.000Z',
    };
    check(Observation.fromJson(json).toJson()).deepEquals(json);
  });
}
