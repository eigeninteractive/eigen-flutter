import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Paths (relative to `lib/`) allowed to talk to the server.
final _allowedCallers = [
  // The transport core: Dio, the interceptors, the socket, the API providers.
  RegExp(r'^core/api/'),
  // Feature and shared data layers (repositories, services).
  RegExp(r'^features/[^/]+/data/'),
  RegExp(r'^shared/data/'),
  // The error vocabulary. `humanize` names `DioException` to tell a transport
  // failure from a server refusal - it classifies a thrown object rather than
  // making a request. Widgets still depend only on `EngineException` and
  // `humanize`, never on Dio.
  RegExp(r'^core/errors/'),
];

/// What "talking to the server" looks like in source: the HTTP client itself,
/// or any of the generated per-resource API classes.
///
/// Deliberately narrower than "imports `eigen_api`". The generated *models* are
/// the app's domain vocabulary - a `GamePlayer` composes a `Player`, a provider
/// caches one - and confining those to the data layer would mean hand-written
/// mirrors and a mapping layer at the boundary, which is the exact thing this
/// architecture rejects. What must stay in the data layer is the *capability to
/// make a request*, not the types that come back.
final _serverAccess = <RegExp>[
  RegExp(r"import 'package:dio/"),
  RegExp(r'\b(?:Games|Social|Me|Players|Bots|BotWebhook)Api\b'),
];

/// This test is the layering boundary. Transport used to live in a separate
/// pure-Dart package where the compiler enforced the split; folding it into
/// `eigen_flutter` traded that for a rule checked here. Keeping the rule is
/// what made the fold safe - without it the boundary is a convention nobody
/// notices breaking.
void main() {
  test('the public barrel exports types, never the API classes', () {
    // A game app depends on `eigen_flutter`, not on `eigen_api`, so the barrel
    // must re-export the wire *vocabulary* a game renders from, without handing
    // apps the ability to call the server directly. A wholesale
    // `export 'package:eigen_api/eigen_api.dart';` would do exactly that, which
    // is why this checks for the `show` clause rather than merely for an export.
    final barrel = File('lib/eigen_flutter.dart').readAsStringSync();

    check(
      because: 'the barrel must re-export the generated types a game needs',
      barrel,
    ).contains("export 'package:eigen_api/eigen_api.dart'");

    final leaked = RegExp(
      r"export 'package:eigen_api/eigen_api\.dart';",
    ).hasMatch(barrel);
    check(
      because:
          'exporting eigen_api wholesale leaks GamesApi/SocialApi/... into every '
          'app that depends on eigen_flutter; keep the explicit `show` list',
      leaked,
    ).isFalse();

    for (final api in const [
      'GamesApi',
      'SocialApi',
      'MeApi',
      'PlayersApi',
      'BotsApi',
      'BotWebhookApi',
      'EigenApi',
    ]) {
      check(
        because: '$api must not be part of the public surface',
        barrel,
      ).not((b) => b.contains(api));
    }
  });

  test('only the data layer talks to the server', () {
    final libDir = Directory('lib');
    check(
      because: 'test must run from the package root',
      libDir.existsSync(),
    ).isTrue();

    final violations = <String>[];
    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      final hits = _serverAccess.where((p) => p.hasMatch(source)).toList();
      if (hits.isEmpty) continue;

      final relative = file.path
          .replaceFirst(RegExp(r'^lib/'), '')
          .replaceAll(r'\', '/');
      if (_allowedCallers.any((p) => p.hasMatch(relative))) continue;
      violations.add(relative);
    }

    check(
      because:
          'these files reach the server outside the data layer; route the '
          'call through a repository instead (generated models may be used '
          'anywhere - only the API classes and Dio are restricted)',
      violations,
    ).isEmpty();
  });
}
