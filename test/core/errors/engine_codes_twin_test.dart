import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Twin-drift guard for the engine's stable error-code registry, which lives
/// three times: the TS `EngineCode` (`_engine/runtime.ts`), the Dart
/// [EngineErrorCodes] (`lib/core/errors/engine_exception.dart`), and the SQL
/// `RAISE ... USING ERRCODE = 'EIGxx'` sites in the migrations. The three are
/// documented as "keep in sync" — this test makes that enforceable by parsing
/// each source and comparing.
void main() {
  const tsPath = 'supabase/functions/_engine/runtime.ts';
  const dartPath = 'lib/core/errors/engine_exception.dart';

  Map<String, String> codesIn(String path, RegExp entry) => {
    for (final match in entry.allMatches(File(path).readAsStringSync()))
      match.group(1)!: match.group(2)!,
  };

  final tsCodes = codesIn(tsPath, RegExp(r'(\w+): "(EIG\d{2})"'));
  final dartCodes = codesIn(
    dartPath,
    RegExp(r"static const (\w+) = '(EIG\d{2})'"),
  );

  test('both registries were found and parsed', () {
    check(because: 'regex found no entries in $tsPath', tsCodes).isNotEmpty();
    check(
      because: 'regex found no entries in $dartPath',
      dartCodes,
    ).isNotEmpty();
  });

  test('the Dart EngineErrorCodes registry matches the TS EngineCode twin', () {
    check(dartCodes).deepEquals(tsCodes);
  });

  test('codes are unique on both sides', () {
    check(tsCodes.values.toSet()).length.equals(tsCodes.length);
    check(dartCodes.values.toSet()).length.equals(dartCodes.length);
  });

  test('every EIG code raised in SQL exists in the registry', () {
    final raised = <String>{};
    final sqlFiles = Directory(
      'supabase/migrations',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.sql'));
    for (final file in sqlFiles) {
      raised.addAll(
        RegExp(
          r"ERRCODE\s*=\s*'(EIG\d{2})'",
        ).allMatches(file.readAsStringSync()).map((m) => m.group(1)!),
      );
    }
    check(because: 'no SQL raises found — path wrong?', raised).isNotEmpty();
    check(
      because: 'SQL raises codes missing from the registry',
      raised.difference(tsCodes.values.toSet()),
    ).isEmpty();
  });
}
