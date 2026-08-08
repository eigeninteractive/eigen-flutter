// Dartdoc selects the two supported package entry points by library name.
// ignore_for_file: unnecessary_library_name

/// Twin-drift fixture runner: the Dart half of the shared JSON fixtures
/// that keep a version unit's TS and Dart [GameRules] twins in sync.
///
/// One fixture file per concern lives under `fixtures/v<N>/*.json` and is
/// consumed by both sides: `@eigeninteractive/testkit` runs each case against
/// the TypeScript unit in the game's Worker (schemas + `applyAction` +
/// `computeObservation` + the two predicates), while this library runs the
/// same file against the Dart twin (generated payload parsing,
/// [GameRules.isValidAction], [GameRules.previewAction], and the predicate
/// twins). A behavioral divergence then fails one side's tests instead of
/// degrading UX in production. The fixture file format is documented in
/// the [EigenInteractive testing guide](https://eigeninteractive.com/docs/build-a-game/testing).
///
/// Loading and running are separate steps on purpose. A fixture file is
/// hand-written JSON, so [loadTwinFixtureSuites] validates it into the typed
/// [TwinFixtureCase] hierarchy first: a missing or mistyped field fails at
/// load with the file, case and field named, rather than surfacing later as a
/// confusing comparison failure blamed on the game's rules. By the time
/// [runTwinFixtureCase] sees a case, every field it reads is known-present and
/// known-typed, so it performs no casting at all.
///
/// This side validates fields it never itself reads (`expected.state`,
/// `participantCount`, ...) as well. Those belong to the TS runner, but a game
/// package may ship only a Dart twin, and then this is the only thing
/// standing between a typo and a silently skipped assertion.
///
/// Framework-free on purpose (no `flutter_test` import), so it can live in
/// `lib/` and be consumed by any app's test suite:
///
/// ```dart
/// void main() {
///   const module = MyGameModule();
///   final root = 'test/fixtures/game';
///   for (final suite in loadTwinFixtureSuites(root)) {
///     final rules = module.versions[suite.schemaVersion];
///     group('twin fixtures v${suite.schemaVersion}', () {
///       for (final fixtureCase in suite.cases) {
///         test(fixtureCase.name, () {
///           expect(rules, isNotNull);
///           expect(runTwinFixtureCase(rules!, fixtureCase), isEmpty);
///         });
///       }
///     });
///   }
/// }
/// ```
///
/// The `expected.observation` comparison relies on value equality (`==`).
/// EigenInteractive's generated payload classes provide deep equality for
/// collections.
library eigen_flutter.testing;

import 'dart:convert';
import 'dart:io';

import 'package:eigen_api/eigen_api.dart' show GameAccess;
import 'package:eigen_flutter/core/game/game_module.dart';

/// One fixture file's cases, all targeting one `schemaVersion` unit.
class TwinFixtureSuite {
  const TwinFixtureSuite({
    required this.path,
    required this.schemaVersion,
    required this.cases,
  });

  /// The fixture file this suite was loaded from, for failure messages.
  final String path;

  /// The `schemaVersion` whose rules unit every case targets.
  final int schemaVersion;

  final List<TwinFixtureCase> cases;
}

/// One validated fixture case. Sealed, so [runTwinFixtureCase] switches
/// exhaustively and an added case kind is a compile error rather than a
/// silently unhandled string.
sealed class TwinFixtureCase {
  const TwinFixtureCase({required this.name});

  /// The case's `name`, used as the test name.
  final String name;
}

/// Exercises the action codec, [GameRules.isValidAction] and, when the game
/// implements optimism, [GameRules.previewAction].
final class ActionCase extends TwinFixtureCase {
  const ActionCase({
    required super.name,
    required this.config,
    required this.state,
    required this.obs,
    required this.action,
    required this.pending,
    required this.playerIndex,
    required this.expectedValid,
    required this.expectedObservation,
  });

  final Map<String, dynamic> config;

  /// The TS runner's `applyAction` input. Read here only as the fallback for
  /// [obs]; a perfect-information game omits `obs` because the two coincide.
  final Map<String, dynamic> state;

  /// The acting seat's observation payload: the fixture's `obs`, or `state`
  /// when the fixture omits it.
  final Map<String, dynamic> obs;

  final Map<String, dynamic> action;
  final List<int> pending;
  final int playerIndex;
  final bool expectedValid;

  /// The actor's post-action view, or null when the fixture records none.
  final Map<String, dynamic>? expectedObservation;
}

/// A [GameRules.ratingPool] predicate case.
final class RatingPoolCase extends TwinFixtureCase {
  const RatingPoolCase({
    required super.name,
    required this.access,
    required this.turnSeconds,
    required this.budgetSeconds,
    required this.incrementSeconds,
    required this.minPlayers,
    required this.maxPlayers,
    required this.config,
    required this.expected,
  });

  final GameAccess access;
  final int? turnSeconds;
  final int? budgetSeconds;
  final int? incrementSeconds;
  final int minPlayers;
  final int maxPlayers;
  final Map<String, dynamic> config;
  final String? expected;
}

/// A [GameRules.botSeatable] predicate case.
final class BotSeatableCase extends TwinFixtureCase {
  const BotSeatableCase({
    required super.name,
    required this.gameConfig,
    required this.botConfig,
    required this.expected,
  });

  final Map<String, dynamic> gameConfig;
  final Map<String, dynamic> botConfig;
  final bool expected;
}

/// Loads every fixture file under [rootPath] (layout: `<root>/v<N>/*.json`),
/// sorted by path for stable test ordering.
///
/// Throws [FormatException] on malformed JSON, and on any fixture that does
/// not match the documented format; a broken fixture should fail loudly and
/// immediately, not silently shrink the suite or fail later as a phantom
/// rules divergence.
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
      parseTwinFixtureSuite(file.path, jsonDecode(file.readAsStringSync())),
  ];
}

/// Validates one fixture file's decoded JSON into a typed suite.
///
/// Exported so a package can lint its fixtures without running them, and so
/// the failure is attributable to a file even when the caller supplies the
/// JSON itself.
TwinFixtureSuite parseTwinFixtureSuite(String path, dynamic json) {
  final root = _object(path, json);
  final cases = _list('$path.cases', root['cases']);
  return TwinFixtureSuite(
    path: path,
    schemaVersion: _int('$path.schemaVersion', root['schemaVersion']),
    cases: [
      for (final (index, raw) in cases.indexed)
        _parseCase('$path.cases[$index]', raw),
    ],
  );
}

TwinFixtureCase _parseCase(String indexed, dynamic raw) {
  final map = _object(indexed, raw);
  // Prefer the case's own name in the location once it is readable: a
  // fixture author finds `cases[3] (seat 0 wins)` faster than an index.
  final name = map['name'];
  final where = name is String ? '$indexed ($name)' : indexed;
  return switch (map['kind']) {
    'action' => _parseActionCase(where, map),
    'ratingPool' => _parseRatingPoolCase(where, map),
    'botSeatable' => _parseBotSeatableCase(where, map),
    final kind => throw FormatException(
      '$where.kind: expected one of action | ratingPool | botSeatable, '
      'got ${jsonEncode(kind)}',
    ),
  };
}

ActionCase _parseActionCase(String where, Map<String, dynamic> map) {
  final expected = _object('$where.expected', map['expected']);
  final state = _object('$where.state', map['state']);
  // Fields only the TS runner consumes. Validated, not stored: a game package
  // may ship no TS twin at all, and then nothing else would catch a typo.
  _optional('$where.expected.state', expected['state'], _object);
  _optional('$where.expected.pending', expected['pending'], _intList);
  _optional('$where.participantCount', map['participantCount'], _int);
  _optional('$where.rngSeed', map['rngSeed'], _string);
  if (expected.containsKey('outcome') && expected['outcome'] != null) {
    _list('$where.expected.outcome', expected['outcome']);
  }
  return ActionCase(
    name: _string('$where.name', map['name']),
    config: _object('$where.config', map['config']),
    state: state,
    obs: _optional('$where.obs', map['obs'], _object) ?? state,
    action: _object('$where.action', map['action']),
    pending: _intList('$where.pending', map['pending']),
    playerIndex: _int('$where.playerIndex', map['playerIndex']),
    expectedValid: _bool('$where.expected.valid', expected['valid']),
    expectedObservation: _optional(
      '$where.expected.observation',
      expected['observation'],
      _object,
    ),
  );
}

RatingPoolCase _parseRatingPoolCase(String where, Map<String, dynamic> map) {
  final accessName = _string('$where.access', map['access']);
  final supportedAccess = GameAccess.values.where(
    (access) => access != GameAccess.unknownDefaultOpenApi,
  );
  final access = supportedAccess.asNameMap()[accessName];
  if (access == null) {
    throw FormatException(
      '$where.access: expected one of '
      '${supportedAccess.map((a) => a.name).join(' | ')}, '
      'got ${jsonEncode(accessName)}',
    );
  }
  return RatingPoolCase(
    name: _string('$where.name', map['name']),
    access: access,
    turnSeconds: _optional('$where.turnSeconds', map['turnSeconds'], _int),
    budgetSeconds: _optional(
      '$where.budgetSeconds',
      map['budgetSeconds'],
      _int,
    ),
    incrementSeconds: _optional(
      '$where.incrementSeconds',
      map['incrementSeconds'],
      _int,
    ),
    minPlayers: _int('$where.minPlayers', map['minPlayers']),
    maxPlayers: _int('$where.maxPlayers', map['maxPlayers']),
    config: _object('$where.config', map['config']),
    expected: _optional('$where.expected', map['expected'], _string),
  );
}

BotSeatableCase _parseBotSeatableCase(String where, Map<String, dynamic> map) {
  return BotSeatableCase(
    name: _string('$where.name', map['name']),
    gameConfig: _object('$where.gameConfig', map['gameConfig']),
    botConfig: _object('$where.botConfig', map['botConfig']),
    expected: _bool('$where.expected', map['expected']),
  );
}

// ── Field readers ───────────────────────────────────────────────────────────

Never _fail(String where, String expected, dynamic got) =>
    throw FormatException('$where: expected $expected, got ${_describe(got)}');

String _describe(dynamic value) => switch (value) {
  null => 'null',
  final List<dynamic> _ => 'an array',
  final Map<dynamic, dynamic> _ => 'an object',
  final String s => 'the string ${jsonEncode(s)}',
  _ => '$value (${value.runtimeType})',
};

Map<String, dynamic> _object(String where, dynamic v) =>
    v is Map<String, dynamic> ? v : _fail(where, 'an object', v);

List<dynamic> _list(String where, dynamic v) =>
    v is List ? v : _fail(where, 'an array', v);

String _string(String where, dynamic v) =>
    v is String ? v : _fail(where, 'a string', v);

bool _bool(String where, dynamic v) =>
    v is bool ? v : _fail(where, 'a boolean', v);

int _int(String where, dynamic v) => v is int ? v : _fail(where, 'an int', v);

List<int> _intList(String where, dynamic v) => [
  for (final (index, n) in _list(where, v).indexed) _int('$where[$index]', n),
];

/// Reads an optional field: absent and explicit null both mean "unspecified".
T? _optional<T>(String where, dynamic v, T Function(String, dynamic) read) =>
    v == null ? null : read(where, v);

// ── Case evaluation ─────────────────────────────────────────────────────────

/// Runs one validated fixture case against the Dart [rules] twin, returning
/// failure descriptions (empty ⇒ the case passes).
///
/// A parse throw (config/observation/action `fromJson`) is reported as a
/// failure, not rethrown: a codec that cannot read the recorded payload is
/// itself twin drift.
List<String> runTwinFixtureCase(
  GameRules<dynamic, dynamic, dynamic> rules,
  TwinFixtureCase fixtureCase,
) => switch (fixtureCase) {
  ActionCase() => _runActionCase(rules, fixtureCase),
  RatingPoolCase() => _runRatingPoolCase(rules, fixtureCase),
  BotSeatableCase() => _runBotSeatableCase(rules, fixtureCase),
};

List<String> _runActionCase(
  GameRules<dynamic, dynamic, dynamic> rules,
  ActionCase c,
) {
  final failures = <String>[];
  final config = _parse('config', () => rules.parseConfig(c.config), failures);
  final obs = _parse(
    'observation',
    () => rules.parseObservation(c.obs),
    failures,
  );
  final action = _parse('action', () => rules.parseAction(c.action), failures);
  if (failures.isNotEmpty) return failures;

  // The codec must round-trip the fixture action: what parseAction reads,
  // serializeAction must write back, or else a submitted move would not
  // match what the TS side validated this fixture against.
  final roundTrip = rules.serializeAction(action);
  if (!_deepEquals(roundTrip, c.action)) {
    failures.add(
      'action codec does not round-trip the fixture action: '
      'serializeAction produced ${jsonEncode(roundTrip)}',
    );
  }

  final valid = rules.isValidAction(
    obs: obs,
    pending: c.pending,
    data: action,
    playerIndex: c.playerIndex,
    config: config,
  );
  if (valid != c.expectedValid) {
    failures.add(
      'isValidAction returned $valid, fixture expects ${c.expectedValid}',
    );
    return failures;
  }
  if (c.expectedValid && c.expectedObservation != null) {
    _checkPreview(rules, c, obs, action, config, failures);
  }
  return failures;
}

/// Compares [GameRules.previewAction] against `expected.observation`, but
/// only when the game implements optimism (a null preview means "this move is
/// server-driven", which is always a correct answer, never drift).
void _checkPreview(
  GameRules<dynamic, dynamic, dynamic> rules,
  ActionCase c,
  dynamic obs,
  dynamic action,
  dynamic config,
  List<String> failures,
) {
  final preview = rules.previewAction(
    obs: obs,
    pending: c.pending,
    data: action,
    playerIndex: c.playerIndex,
    config: config,
  );
  if (preview == null) return;
  final expectedObs = _parse(
    'expected.observation',
    () => rules.parseObservation(c.expectedObservation!),
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
  RatingPoolCase c,
) {
  final pool = rules.ratingPool(
    RatingPoolArgs(
      access: c.access,
      turnSeconds: c.turnSeconds,
      budgetSeconds: c.budgetSeconds,
      incrementSeconds: c.incrementSeconds,
      minPlayers: c.minPlayers,
      maxPlayers: c.maxPlayers,
      config: c.config,
    ),
  );
  if (pool == c.expected) return const [];
  return [
    'ratingPool returned ${jsonEncode(pool)}, fixture expects '
        '${jsonEncode(c.expected)}',
  ];
}

List<String> _runBotSeatableCase(
  GameRules<dynamic, dynamic, dynamic> rules,
  BotSeatableCase c,
) {
  final seatable = rules.botSeatable(
    BotSeatableArgs(gameConfig: c.gameConfig, botConfig: c.botConfig),
  );
  if (seatable == c.expected) return const [];
  return ['botSeatable returned $seatable, fixture expects ${c.expected}'];
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
