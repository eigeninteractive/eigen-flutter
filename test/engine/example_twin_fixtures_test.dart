import 'package:checks/checks.dart';
import 'package:eigen_engine/core/game/game_module.dart';
import 'package:eigen_engine/testing/twin_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/example_rules.dart';

/// Dogfoods the twin-fixture pipeline end to end: the shared fixtures under
/// `supabase/functions/_lib/game/fixtures/` run here against the Dart
/// [ExampleRules] twin, and in `_tests/twin_fixtures_test.ts` against the TS
/// example unit. Downstream apps copy this wiring for their own game.
void main() {
  const versions = <int, GameRules<dynamic, dynamic, dynamic>>{
    1: ExampleRules(),
  };
  final suites = loadTwinFixtureSuites('supabase/functions/_lib/game/fixtures');

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
          check(runTwinFixtureCase(rules!, fixtureCase.json)).isEmpty();
        });
      }
    });
  }
}
