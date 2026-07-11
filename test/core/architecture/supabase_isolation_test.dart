import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Paths (relative to `lib/`) allowed to import `package:supabase_flutter`.
///
/// The Supabase contract is confined to the data layer plus bootstrap so a
/// backend swap touches only these files. Everything above them consumes
/// domain types (freezed models, `AuthUser`, `EngineException`).
final _allowedImporters = [
  // Bootstrap: Supabase.initialize with the app's config.
  RegExp(r'^app_runner\.dart$'),
  // Feature and shared data layers (repositories, services, models).
  RegExp(r'^features/[^/]+/data/'),
  RegExp(r'^shared/data/'),
  // The single injection seam handing the client to repositories.
  RegExp(r'^shared/providers/supabase_client_provider\.dart$'),
];

void main() {
  test('supabase_flutter is imported only by the data layer + bootstrap', () {
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
      if (!file.readAsStringSync().contains("import 'package:supabase_")) {
        continue;
      }
      final relative = file.path
          .replaceFirst(RegExp(r'^lib/'), '')
          .replaceAll(r'\', '/');
      final allowed = _allowedImporters.any((p) => p.hasMatch(relative));
      if (!allowed) violations.add(relative);
    }

    check(
      because:
          'these files import supabase_flutter outside the data layer; '
          'route their backend access through a repository instead',
      violations,
    ).isEmpty();
  });
}
