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

  test('Observation parses the action-response frame (to_jsonb row shape)', () {
    // Captured verbatim from a local e2e drive: the caller's committed frame
    // that engine_commit_action returns (to_jsonb of the observations row) and
    // the action route hands back. Must stay parseable — submitAction feeds it
    // into the same pipeline as Realtime records, which share this shape.
    final json = <String, Object?>{
      'data': {'moves': 1},
      'bot_id': null,
      'game_id': 'af535049-c3f5-428f-8633-483ef64b6f63',
      'user_id': 'fc1305cc-e22e-4339-91e3-32e1ba5fbba5',
      'version': 1,
      'created_at': '2026-07-10T08:48:38.157709+00:00',
      'player_index': 0,
      'player_times': null,
      'turn_deadline': null,
      'pending_players': <int>[],
      'turn_started_at': null,
    };
    final observation = Observation.fromJson(json);
    check(observation.version).equals(1);
    check(observation.playerIndex).equals(0);
    check(observation.data).deepEquals({'moves': 1});
    check(observation.pendingPlayers).isEmpty();
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
