/// Twin-drift fixture runner — the Dart half of the shared JSON fixtures
/// that keep a version unit's TS and Dart [GameRules] twins in sync.
///
/// One fixture file per concern lives beside the TS version units at
/// `supabase/functions/_lib/game/fixtures/v<N>/*.json` and is consumed by
/// BOTH sides: the vendored `_engine/twin-fixtures.ts` runs each case against
/// the TS unit (schemas + `applyAction` + `computeObservation` + the two
/// predicates), while this library runs the same file against the Dart twin
/// (the payload codec, [GameRules.isValidAction], [GameRules.previewAction],
/// and the predicate twins). A behavioral divergence then fails one side's
/// tests instead of degrading UX in production. The fixture file format is
/// documented in `_engine/twin-fixtures.ts`, the TS half.
///
/// Framework-free on purpose (no `flutter_test` import), so it can live in
/// `lib/` and be consumed by any app's test suite:
///
/// ```dart
/// void main() {
///   const module = MyGameModule();
///   final root = 'supabase/functions/_lib/game/fixtures';
///   for (final suite in loadTwinFixtureSuites(root)) {
///     final rules = module.versions[suite.schemaVersion];
///     group('twin fixtures v${suite.schemaVersion}', () {
///       for (final fixtureCase in suite.cases) {
///         test(fixtureCase.name, () {
///           expect(rules, isNotNull);
///           expect(runTwinFixtureCase(rules!, fixtureCase.json), isEmpty);
///         });
///       }
///     });
///   }
/// }
/// ```
///
/// The `expected.observation` comparison relies on the observation type's
/// value equality (`==`) — Freezed models provide this; hand-written types
/// must override `==`/`hashCode` for preview cases to be checkable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_api/eigen_api.dart' show GameAccess;

/// One fixture file's cases, all targeting one `schema_version` unit.
class TwinFixtureSuite {
  const TwinFixtureSuite({
    required this.path,
    required this.schemaVersion,
    required this.cases,
  });

  /// The fixture file this suite was loaded from, for failure messages.
  final String path;

  /// The `schema_version` whose rules unit every case targets.
  final int schemaVersion;

  final List<TwinFixtureCase> cases;
}

/// One named fixture case, kept as raw JSON for [runTwinFixtureCase].
class TwinFixtureCase {
  const TwinFixtureCase({required this.name, required this.json});

  final String name;
  final Map<String, dynamic> json;
}

/// Loads every fixture file under [rootPath] (layout: `<root>/v<N>/*.json`),
/// sorted by path for stable test ordering.
///
/// Throws [FormatException] on malformed JSON and [TypeError] on a file
/// missing `schemaVersion`/`cases` — a broken fixture should fail loudly, not
/// silently shrink the suite.
List<TwinFixtureSuite> loadTwinFixtureSuites(String rootPath) {
  final files =
      Directory(rootPath)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      _parseSuite(file.path, jsonDecode(file.readAsStringSync())),
  ];
}

TwinFixtureSuite _parseSuite(String path, dynamic json) {
  final map = json as Map<String, dynamic>;
  return TwinFixtureSuite(
    path: path,
    schemaVersion: map['schemaVersion'] as int,
    cases: [
      for (final c in map['cases'] as List)
        TwinFixtureCase(
          name: (c as Map<String, dynamic>)['name'] as String,
          json: c,
        ),
    ],
  );
}

/// Runs one fixture case against the Dart [rules] twin, returning failure
/// descriptions (empty ⇒ the case passes).
///
/// A parse throw (config/observation/action `fromJson`) is reported as a
/// failure, not rethrown — a codec that cannot read the recorded payload is
/// itself twin drift.
List<String> runTwinFixtureCase(
  GameRules<dynamic, dynamic, dynamic> rules,
  Map<String, dynamic> caseJson,
) {
  switch (caseJson['kind']) {
    case 'action':
      return _runActionCase(rules, caseJson);
    case 'ratingPool':
      return _runRatingPoolCase(rules, caseJson);
    case 'botSeatable':
      return _runBotSeatableCase(rules, caseJson);
    case final kind:
      return [
        'unknown case kind "$kind" — expected '
            'action | ratingPool | botSeatable',
      ];
  }
}

List<String> _runActionCase(
  GameRules<dynamic, dynamic, dynamic> rules,
  Map<String, dynamic> c,
) {
  final failures = <String>[];
  final rawAction = c['action'] as Map<String, dynamic>;
  final config = _parse(
    'config',
    () => rules.parseConfig(c['config'] as Map<String, dynamic>),
    failures,
  );
  final obs = _parse(
    'observation',
    () => rules.parseObservation(
      (c['obs'] ?? c['state']) as Map<String, dynamic>,
    ),
    failures,
  );
  final action = _parse('action', () => rules.parseAction(rawAction), failures);
  if (failures.isNotEmpty) return failures;

  // The codec must round-trip the fixture action: what parseAction reads,
  // serializeAction must write back — otherwise a submitted move would not
  // match what the TS side validated this fixture against.
  final roundTrip = rules.serializeAction(action);
  if (!_deepEquals(roundTrip, rawAction)) {
    failures.add(
      'action codec does not round-trip the fixture action — '
      'serializeAction produced ${jsonEncode(roundTrip)}',
    );
  }

  final expected = c['expected'] as Map<String, dynamic>;
  final expectedValid = expected['valid'] as bool;
  final pending = (c['pending'] as List).cast<int>();
  final playerIndex = c['playerIndex'] as int;
  final valid = rules.isValidAction(
    obs: obs,
    pending: pending,
    data: action,
    playerIndex: playerIndex,
    config: config,
  );
  if (valid != expectedValid) {
    failures.add(
      'isValidAction returned $valid, fixture expects $expectedValid',
    );
    return failures;
  }
  if (expectedValid && expected['observation'] != null) {
    _checkPreview(rules, c, obs, action, config, failures);
  }
  return failures;
}

/// Compares [GameRules.previewAction] against `expected.observation` — but
/// only when the game implements optimism (a null preview means "this move is
/// server-driven", which is always a correct answer, never drift).
void _checkPreview(
  GameRules<dynamic, dynamic, dynamic> rules,
  Map<String, dynamic> c,
  dynamic obs,
  dynamic action,
  dynamic config,
  List<String> failures,
) {
  final preview = rules.previewAction(
    obs: obs,
    pending: (c['pending'] as List).cast<int>(),
    data: action,
    playerIndex: c['playerIndex'] as int,
    config: config,
  );
  if (preview == null) return;
  final expectedJson =
      (c['expected'] as Map<String, dynamic>)['observation']
          as Map<String, dynamic>;
  final expectedObs = _parse(
    'expected.observation',
    () => rules.parseObservation(expectedJson),
    failures,
  );
  if (failures.isNotEmpty) return;
  if (preview != expectedObs) {
    failures.add(
      'previewAction diverges from the expected observation '
      '(got $preview, expected $expectedObs)',
    );
  }
}

List<String> _runRatingPoolCase(
  GameRules<dynamic, dynamic, dynamic> rules,
  Map<String, dynamic> c,
) {
  final failures = <String>[];
  final accessName = c['access'] as String;
  final access = GameAccess.values.asNameMap()[accessName];
  if (access == null) {
    return ['unknown access "$accessName" in ratingPool case'];
  }
  final pool = rules.ratingPool(
    RatingPoolArgs(
      access: access,
      turnSeconds: c['turnSeconds'] as int?,
      budgetSeconds: c['budgetSeconds'] as int?,
      incrementSeconds: c['incrementSeconds'] as int?,
      minPlayers: c['minPlayers'] as int,
      maxPlayers: c['maxPlayers'] as int,
      config: c['config'] as Map<String, dynamic>,
    ),
  );
  final expected = c['expected'] as String?;
  if (pool != expected) {
    failures.add(
      'ratingPool returned ${jsonEncode(pool)}, fixture expects '
      '${jsonEncode(expected)}',
    );
  }
  return failures;
}

List<String> _runBotSeatableCase(
  GameRules<dynamic, dynamic, dynamic> rules,
  Map<String, dynamic> c,
) {
  final seatable = rules.botSeatable(
    BotSeatableArgs(
      gameConfig: c['gameConfig'] as Map<String, dynamic>,
      botConfig: c['botConfig'] as Map<String, dynamic>,
    ),
  );
  final expected = c['expected'] as bool;
  if (seatable == expected) return const [];
  return ['botSeatable returned $seatable, fixture expects $expected'];
}

/// Runs one codec step, converting a throw into a recorded failure.
T? _parse<T>(String what, T Function() parse, List<String> failures) {
  try {
    return parse();
  } catch (error) {
    failures.add('Dart codec failed to parse the fixture $what: $error');
    return null;
  }
}

/// Structural JSON equality: maps compare by key set, lists in order.
bool _deepEquals(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    return a.keys.every((k) => b.containsKey(k) && _deepEquals(a[k], b[k]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
