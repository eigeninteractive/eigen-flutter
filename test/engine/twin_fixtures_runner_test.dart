import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:eigen_api/eigen_api.dart' show GameAccess;
import 'package:eigen_flutter/testing/twin_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// Unit tests of the Dart twin-fixture runner itself, driven by the sample
/// tic-tac-toe rules.
///
/// Two halves, matching the two stages the library separates: parsing (a
/// malformed fixture must fail at load, naming the offending field) and
/// evaluation (every checked surface, codec round-trip, legality, preview and
/// predicates, must both pass on agreement and produce a failure message on
/// divergence). The evaluation tests build typed cases directly, so they
/// exercise the runner without going through the parser.
void main() {
  const rules = SampleRules();

  void expectSingleFailure(List<String> result, String fragment) {
    check(result).length.equals(1);
    check(result.first).contains(fragment);
  }

  final emptyBoard = List<int?>.filled(9, null);

  ActionCase actionCase({
    List<int?>? board,
    List<int> pending = const [0],
    int playerIndex = 0,
    Map<String, dynamic> action = const {'cell': 4},
    Map<String, dynamic>? obs,
    required bool valid,
    Map<String, dynamic>? observation,
  }) {
    final state = <String, dynamic>{'board': board ?? emptyBoard};
    return ActionCase(
      name: 'case',
      config: const {},
      state: state,
      obs: obs ?? state,
      action: action,
      pending: pending,
      playerIndex: playerIndex,
      expectedValid: valid,
      expectedObservation: observation,
    );
  }

  group('action cases', () {
    test('passes when legality and preview both agree', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(
          valid: true,
          observation: {
            'board': [null, null, null, null, 0, null, null, null, null],
          },
        ),
      );
      check(result).isEmpty();
    });

    test('agrees on an illegal move', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(pending: [1], valid: false),
      );
      check(result).isEmpty();
    });

    test('fails when isValidAction disagrees with expected.valid', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(pending: [1], valid: true),
      );
      expectSingleFailure(result, 'isValidAction returned false');
    });

    test('fails when the preview diverges from expected.observation', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(
          valid: true,
          observation: {
            'board': [0, null, null, null, null, null, null, null, null],
          },
        ),
      );
      expectSingleFailure(result, 'previewAction diverges');
    });

    test('fails when the action codec does not round-trip', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(action: {'cell': 4, 'noise': true}, valid: true),
      );
      expectSingleFailure(result, 'does not round-trip');
    });

    test('reports a codec parse throw as a failure', () {
      final result = runTwinFixtureCase(
        rules,
        actionCase(obs: {'wrong': 1}, valid: true),
      );
      expectSingleFailure(result, 'failed to parse the fixture observation');
    });
  });

  group('predicate cases', () {
    test('ratingPool agreement passes and divergence fails', () {
      RatingPoolCase ratingCase(GameAccess access, String? expected) =>
          RatingPoolCase(
            name: 'case',
            access: access,
            turnSeconds: null,
            budgetSeconds: null,
            incrementSeconds: null,
            minPlayers: 2,
            maxPlayers: 2,
            config: const {},
            expected: expected,
          );
      check(
        runTwinFixtureCase(rules, ratingCase(GameAccess.public, 'casual')),
      ).isEmpty();
      check(
        runTwinFixtureCase(rules, ratingCase(GameAccess.private, null)),
      ).isEmpty();
      expectSingleFailure(
        runTwinFixtureCase(rules, ratingCase(GameAccess.public, 'blitz')),
        'ratingPool returned "casual"',
      );
    });

    test('botSeatable agreement passes and divergence fails', () {
      BotSeatableCase botCase(bool expected) => BotSeatableCase(
        name: 'case',
        gameConfig: const {},
        botConfig: const {},
        expected: expected,
      );
      check(runTwinFixtureCase(rules, botCase(true))).isEmpty();
      expectSingleFailure(
        runTwinFixtureCase(rules, botCase(false)),
        'botSeatable returned true',
      );
    });
  });

  group('parsing', () {
    /// A well-formed single-case file, with [patch] merged into the case.
    /// A key mapped to null is removed, so a test can drop a required field.
    Map<String, dynamic> file(Map<String, dynamic> patch) {
      final kase = <String, dynamic>{
        'kind': 'action',
        'name': 'a case',
        'config': <String, dynamic>{},
        'state': <String, dynamic>{'board': emptyBoard},
        'pending': [0],
        'playerIndex': 0,
        'action': <String, dynamic>{'cell': 4},
        'expected': <String, dynamic>{'valid': true},
        ...patch,
      }..removeWhere((_, v) => v == null);
      return {
        'schemaVersion': 1,
        'cases': [kase],
      };
    }

    void expectParseError(Map<String, dynamic> json, String fragment) {
      check(() => parseTwinFixtureSuite('f.json', json))
          .throws<FormatException>()
          .has((e) => e.message, 'message')
          .contains(fragment);
    }

    test('accepts a well-formed file', () {
      final suite = parseTwinFixtureSuite('f.json', file(const {}));
      check(suite.schemaVersion).equals(1);
      check(suite.cases.single).isA<ActionCase>();
    });

    test('defaults obs to state when the fixture omits it', () {
      final kase = parseTwinFixtureSuite('f.json', file(const {})).cases.single;
      check(kase).isA<ActionCase>().has((c) => c.obs, 'obs').deepEquals({
        'board': emptyBoard,
      });
    });

    test('names the file, the case and the field', () {
      expectParseError(
        file(const {'playerIndex': null}),
        'f.json.cases[0] (a case).playerIndex: expected an int, got null',
      );
    });

    test('rejects a mistyped element inside a list', () {
      expectParseError(
        file(const {
          'pending': ['0'],
        }),
        'pending[0]: expected an int',
      );
    });

    test('rejects an unknown case kind', () {
      expectParseError(
        file(const {'kind': 'mystery'}),
        '.kind: expected one of',
      );
    });

    test('rejects a missing expected.valid', () {
      expectParseError(
        file(const {'expected': <String, dynamic>{}}),
        'expected.valid: expected a boolean',
      );
    });

    test('rejects an unknown access on a ratingPool case', () {
      expectParseError({
        'schemaVersion': 1,
        'cases': [
          {
            'kind': 'ratingPool',
            'name': 'r',
            'access': 'publik',
            'minPlayers': 2,
            'maxPlayers': 2,
            'config': <String, dynamic>{},
            'expected': null,
          },
        ],
      }, '.access: expected one of');
    });

    test('validates fields only the TS runner consumes', () {
      // A game package may ship no TS twin, so this side is the only thing
      // that would catch the typo.
      expectParseError(
        file(const {
          'expected': <String, dynamic>{
            'valid': true,
            'pending': ['1'],
          },
        }),
        'expected.pending[0]: expected an int',
      );
    });
  });

  test('loadTwinFixtureSuites reads <root>/v<N>/*.json in stable order', () {
    final root = Directory.systemTemp.createTempSync('twin_fixtures');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/v1').createSync();
    Map<String, dynamic> botFile(String name) => {
      'schemaVersion': 1,
      'cases': [
        {
          'kind': 'botSeatable',
          'name': name,
          'gameConfig': <String, dynamic>{},
          'botConfig': <String, dynamic>{},
          'expected': true,
        },
      ],
    };
    File(
      '${root.path}/v1/b.json',
    ).writeAsStringSync(jsonEncode(botFile('second')));
    File(
      '${root.path}/v1/a.json',
    ).writeAsStringSync(jsonEncode(botFile('first')));

    final suites = loadTwinFixtureSuites(root.path);
    check(suites).length.equals(2);
    check(suites.first.schemaVersion).equals(1);
    check(suites.first.cases.single.name).equals('first');
    check(suites.last.cases.single.name).equals('second');
  });
}
