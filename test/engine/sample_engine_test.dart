import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  const rules = SampleRules();
  const config = SampleConfig();
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
        rules.isValidAction(
          obs: empty,
          pending: [0],
          data: const SampleAction(4),
          playerIndex: 0,
          config: config,
        ),
      ).isTrue();
    });

    test("rejects when it is not the player's turn", () {
      check(
        rules.isValidAction(
          obs: empty,
          pending: [1],
          data: const SampleAction(4),
          playerIndex: 0,
          config: config,
        ),
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
      check(
        rules.isValidAction(
          obs: obs,
          pending: [1],
          data: const SampleAction(0),
          playerIndex: 1,
          config: config,
        ),
      ).isFalse();
    });

    test('rejects an out-of-range cell', () {
      check(
        rules.isValidAction(
          obs: empty,
          pending: [0],
          data: const SampleAction(9),
          playerIndex: 0,
          config: config,
        ),
      ).isFalse();
    });
  });

  test('parseObservation reads the board payload', () {
    final obs = rules.parseObservation(<String, dynamic>{
      'board': [0, null, 1],
    });
    check(obs.board).deepEquals([0, null, 1]);
  });

  test('action codec round-trips through JSON', () {
    final json = rules.serializeAction(const SampleAction(4));
    check(rules.parseAction(json).cell).equals(4);
  });

  group('GameModule.supportsSchema', () {
    const module = SampleModule(); // versions == {1}

    test('accepts a version this build ships rules for', () {
      check(module.supportsSchema(1)).isTrue();
      check(module.latestSchemaVersion).equals(1);
    });

    test('rejects a version with no rules entry (newer build or retired)', () {
      check(module.supportsSchema(2)).isFalse();
    });
  });

  group('GameModule defaults', () {
    const module = SampleModule();

    test('latestRules is the unit at the highest version key', () {
      check(module.latestRules).isA<SampleRules>();
    });

    test('playersForConfig falls back to the creation spec bounds', () {
      check(module.playersForConfig(const {})).equals((2, 2));
    });
  });

  test('UnsupportedGameSchemaException names both versions', () {
    const exception = UnsupportedGameSchemaException(
      gameSchema: 3,
      supportedSchema: 2,
    );
    check(
      exception.toString(),
    ).contains('no rules for game schema 3 (latest supported: 2)');
  });
}
