import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/game/game_creation_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PerActionConfig', () {
    test('rejects minSeconds below the infra floor', () {
      check(
        () => PerActionConfig(minSeconds: 10, maxSeconds: 300),
      ).throws<AssertionError>();
    });

    test('rejects maxSeconds not greater than minSeconds', () {
      check(
        () => PerActionConfig(minSeconds: 60, maxSeconds: 60),
      ).throws<AssertionError>();
    });

    test('defaults minSeconds to the infra floor', () {
      check(
        PerActionConfig(maxSeconds: 300).minSeconds,
      ).equals(kMinTurnSeconds);
    });
  });

  group('BudgetConfig', () {
    test('rejects minBudgetSeconds below the infra floor', () {
      check(
        () => BudgetConfig(minBudgetSeconds: 60, maxBudgetSeconds: 600),
      ).throws<AssertionError>();
    });

    test('rejects maxBudgetSeconds not greater than minBudgetSeconds', () {
      check(
        () => BudgetConfig(maxBudgetSeconds: kMinBudgetSeconds),
      ).throws<AssertionError>();
    });
  });

  group('GameCreationSpec', () {
    test('defaults to a single Untimed timing option', () {
      const spec = GameCreationSpec(minPlayers: 2, maxPlayers: 4);
      check(spec.timingConfigs.keys.single).equals('Untimed');
      check(spec.timingConfigs['Untimed']).isA<UntimedConfig>();
    });
  });
}
