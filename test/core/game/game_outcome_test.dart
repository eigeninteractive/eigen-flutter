import 'package:checks/checks.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GameOutcome round-trips with an OutcomeResult enum', () {
    final json = <String, Object?>{
      'game_id': 'g1',
      'player_index': 0,
      'user_id': 'u1',
      'bot_id': null,
      'result': 'win',
      'score': 1.0,
      'placement': 1,
      'team_index': 0,
    };
    check(GameOutcome.fromJson(json).toJson()).deepEquals(json);
  });

  test('decodes each OutcomeResult value', () {
    for (final name in const ['win', 'loss', 'draw', 'eliminated']) {
      final outcome = GameOutcome.fromJson(<String, Object?>{
        'game_id': 'g',
        'player_index': 0,
        'result': name,
        'placement': 1,
        'team_index': 0,
      });
      check(outcome.result.name).equals(name);
    }
  });
}
