import 'package:checks/checks.dart';
import 'package:eigen_engine/features/game/data/models/replay_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReplayFrame parses a move frame from the replay route', () {
    // The `game/replay` response shape: game payloads (data, action_data) are
    // opaque maps, action_* describe the producing transition.
    final json = <String, Object?>{
      'version': 3,
      'data': {
        'cells': [0, 1, null],
      },
      'pending_players': [1],
      'created_at': '2026-07-10T08:48:38.157709+00:00',
      'action_type': 'user',
      'action_kind': 'game',
      'action_data': {'position': 4},
      'action_player_index': 0,
    };

    final frame = ReplayFrame.fromJson(json);

    check(frame.version).equals(3);
    check(frame.data).deepEquals({
      'cells': [0, 1, null],
    });
    check(frame.pendingPlayers).deepEquals([1]);
    check(frame.actionType).equals('user');
    check(frame.actionKind).equals('game');
    check(frame.actionData).isNotNull().deepEquals({'position': 4});
    check(frame.actionPlayerIndex).equals(0);
  });

  test('ReplayFrame parses the initial frame (no producing action)', () {
    final json = <String, Object?>{
      'version': 0,
      'data': <String, Object?>{},
      'pending_players': [0, 1],
      'created_at': '2026-07-10T08:48:38.157709+00:00',
      'action_type': null,
      'action_kind': null,
      'action_data': null,
      'action_player_index': null,
    };

    final frame = ReplayFrame.fromJson(json);

    check(frame.version).equals(0);
    check(frame.actionType).isNull();
    check(frame.actionKind).isNull();
    check(frame.actionData).isNull();
    check(frame.actionPlayerIndex).isNull();
  });

  test('ReplayFrame parses a system lifecycle frame (null performer seat)', () {
    // A timeout: system-performed, so action_player_index is null even though
    // action_kind is lifecycle.
    final json = <String, Object?>{
      'version': 5,
      'data': <String, Object?>{},
      'pending_players': <int>[],
      'created_at': '2026-07-10T08:48:38.157709+00:00',
      'action_type': 'system',
      'action_kind': 'lifecycle',
      'action_data': {'type': 'timeout'},
      'action_player_index': null,
    };

    final frame = ReplayFrame.fromJson(json);

    check(frame.actionKind).equals('lifecycle');
    check(frame.actionType).equals('system');
    check(frame.actionPlayerIndex).isNull();
  });
}
