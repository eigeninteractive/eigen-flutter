import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Paths (relative to `lib/`) allowed to import the transport packages.
///
/// The engine's HTTP contract is confined to the data layer plus the transport
/// core, so a backend change touches only these files. Everything above them
/// consumes domain types.
///
/// This test *is* the layering boundary. Transport used to live in a separate
/// pure-Dart package, where the compiler enforced the split; folding it into
/// `eigen_flutter` traded that for a rule checked here. Keeping the rule is
/// what made the fold safe — without it the boundary is a convention nobody
/// notices breaking.
final _allowedImporters = [
  // The transport core: Dio, the interceptors, and the API providers.
  RegExp(r'^core/api/'),
  // Feature and shared data layers (repositories, services).
  RegExp(r'^features/[^/]+/data/'),
  RegExp(r'^shared/data/'),
  // The error vocabulary. `ErrorCode` is a generated type but a domain concept
  // — the stable contract the whole app dispatches on — and `humanize` needs
  // `DioException` to tell a transport failure from a server refusal. Widgets
  // still depend only on `EngineException` and `humanize`, never on Dio.
  RegExp(r'^core/errors/'),
];

/// Packages that may only be imported from the paths above.
const _restrictedPackages = ['eigen_api', 'dio'];

void main() {
  test('transport packages are imported only by the data layer', () {
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
      final imported = _restrictedPackages
          .where((p) => source.contains("import 'package:$p/"))
          .toList();
      if (imported.isEmpty) continue;

      final relative = file.path
          .replaceFirst(RegExp(r'^lib/'), '')
          .replaceAll(r'\', '/');
      final allowed = _allowedImporters.any((p) => p.hasMatch(relative));
      if (!allowed) violations.add('$relative (${imported.join(', ')})');
    }

    check(
      because:
          'these files import transport packages outside the data layer; '
          'route their backend access through a repository instead',
      violations,
    ).isEmpty();
  });
}
