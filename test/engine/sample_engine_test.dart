import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  final engine = SampleEngine();
  const empty = SampleObservation([
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  ]);

  group('isValidAction', () {
    test('allows a pending player to play an empty cell', () {
      check(
        engine.isValidAction(empty, [0], const SampleAction(4), 0),
      ).isTrue();
    });

    test("rejects when it is not the player's turn", () {
      check(
        engine.isValidAction(empty, [1], const SampleAction(4), 0),
      ).isFalse();
    });

    test('rejects an already-occupied cell', () {
      const obs = SampleObservation([
        0,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
      ]);
      check(engine.isValidAction(obs, [1], const SampleAction(0), 1)).isFalse();
    });

    test('rejects an out-of-range cell', () {
      check(
        engine.isValidAction(empty, [0], const SampleAction(9), 0),
      ).isFalse();
    });
  });

  test('parseObservation reads the board payload', () {
    final obs = engine.parseObservation(<String, dynamic>{
      'board': [0, null, 1],
    });
    check(obs.board).deepEquals([0, null, 1]);
  });

  group('GameModule.supportsSchema', () {
    const module = SampleModule(); // schemaVersion == 1

    test('accepts its own and older schema versions', () {
      check(module.supportsSchema(1)).isTrue();
    });

    test('rejects a newer schema version (created by a newer build)', () {
      check(module.supportsSchema(2)).isFalse();
    });
  });
}
