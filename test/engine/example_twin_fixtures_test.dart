import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_flutter/testing/twin_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/example_rules.dart';

/// Dogfoods the twin-fixture pipeline end to end: the shared fixtures under
/// `test/fixtures/game/` run here against the Dart [ExampleRules] twin. A real
/// game runs the same files against its authoritative TS unit via
/// `@eigen/testkit`; this package has no Worker, so only the Dart half runs
/// here, enough to keep [loadTwinFixtureSuites] and [runTwinFixtureCase]
/// honest. Downstream apps copy this wiring for their own game.
void main() {
  const versions = <int, GameRules<dynamic, dynamic, dynamic>>{
    1: ExampleRules(),
  };
  final suites = loadTwinFixtureSuites('test/fixtures/game');

  test('the example fixture suite is present', () {
    check(because: 'test must run from the package root', suites).isNotEmpty();
  });

  for (final suite in suites) {
    final rules = versions[suite.schemaVersion];
    group('twin fixtures v${suite.schemaVersion} (${suite.path})', () {
      for (final fixtureCase in suite.cases) {
        test(fixtureCase.name, () {
          check(
            because: 'no Dart rules unit for v${suite.schemaVersion}',
            rules,
          ).isNotNull();
          check(runTwinFixtureCase(rules!, fixtureCase)).isEmpty();
        });
      }
    });
  }
}
