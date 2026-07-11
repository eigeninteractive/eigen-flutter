import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:eigen_engine/testing/twin_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// Unit tests of the Dart twin-fixture runner itself, driven by the sample
/// tic-tac-toe rules: every checked surface (codec round-trip, legality,
/// preview, predicates) must both pass on agreement and produce a failure
/// message on divergence.
void main() {
  const rules = SampleRules();

  void expectSingleFailure(List<String> result, String fragment) {
    check(result).length.equals(1);
    check(result.first).contains(fragment);
  }

  final emptyBoard = List<int?>.filled(9, null);

  Map<String, dynamic> actionCase({
    List<int?>? board,
    List<int> pending = const [0],
    int playerIndex = 0,
    Map<String, dynamic> action = const {'cell': 4},
    required Map<String, dynamic> expected,
  }) => {
    'kind': 'action',
    'name': 'case',
    'config': <String, dynamic>{},
    'state': {'board': board ?? emptyBoard},
    'pending': pending,
    'playerIndex': playerIndex,
    'action': action,
    'expected': expected,
  };

  group('action cases', () {
    test('passes when legality and preview both agree', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(
          expected: {
            'valid': true,
            'observation': {
              'board': [null, null, null, null, 0, null, null, null, null],
            },
          },
        ),
      );
      check(result).isEmpty();
    });

    test('agrees on an illegal move', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(pending: [1], expected: {'valid': false}),
      );
      check(result).isEmpty();
    });

    test('fails when isValidAction disagrees with expected.valid', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(pending: [1], expected: {'valid': true}),
      );
      expectSingleFailure(result, 'isValidAction returned false');
    });

    test('fails when the preview diverges from expected.observation', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(
          expected: {
            'valid': true,
            'observation': {
              'board': [0, null, null, null, null, null, null, null, null],
            },
          },
        ),
      );
      expectSingleFailure(result, 'previewAction diverges');
    });

    test('fails when the action codec does not round-trip', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(
          action: {'cell': 4, 'noise': true},
          expected: {'valid': true},
        ),
      );
      expectSingleFailure(result, 'does not round-trip');
    });

    test('reports a codec parse throw as a failure', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(expected: {'valid': true})
          ..['state'] = <String, dynamic>{'wrong': 1},
      );
      expectSingleFailure(result, 'failed to parse the fixture observation');
    });
  });

  group('predicate cases', () {
    test('ratingPool agreement passes and divergence fails', () {
      Map<String, dynamic> ratingCase(String access, String? expected) => {
        'kind': 'ratingPool',
        'name': 'case',
        'access': access,
        'minPlayers': 2,
        'maxPlayers': 2,
        'config': <String, dynamic>{},
        'expected': expected,
      };
      check(
        runTwinFixtureCase(rules, ratingCase('public', 'casual')),
      ).isEmpty();
      check(runTwinFixtureCase(rules, ratingCase('private', null))).isEmpty();
      expectSingleFailure(
        runTwinFixtureCase(rules, ratingCase('public', 'blitz')),
        'ratingPool returned "casual"',
      );
    });

    test('botSeatable agreement passes and divergence fails', () {
      Map<String, dynamic> botCase(bool expected) => {
        'kind': 'botSeatable',
        'name': 'case',
        'gameConfig': <String, dynamic>{},
        'botConfig': <String, dynamic>{},
        'expected': expected,
      };
      check(runTwinFixtureCase(rules, botCase(true))).isEmpty();
      expectSingleFailure(
        runTwinFixtureCase(rules, botCase(false)),
        'botSeatable returned true',
      );
    });
  });

  test('an unknown case kind is a failure', () {
    expectSingleFailure(
      runTwinFixtureCase(rules, {'kind': 'mystery', 'name': 'case'}),
      'unknown case kind "mystery"',
    );
  });

  test('loadTwinFixtureSuites reads <root>/v<N>/*.json in stable order', () {
    final root = Directory.systemTemp.createTempSync('twin_fixtures');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/v1').createSync();
    File('${root.path}/v1/b.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'cases': [
          {'kind': 'botSeatable', 'name': 'second'},
        ],
      }),
    );
    File('${root.path}/v1/a.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'cases': [
          {'kind': 'botSeatable', 'name': 'first'},
        ],
      }),
    );

    final suites = loadTwinFixtureSuites(root.path);
    check(suites).length.equals(2);
    check(suites.first.schemaVersion).equals(1);
    check(suites.first.cases.single.name).equals('first');
    check(suites.last.cases.single.name).equals('second');
  });
}
