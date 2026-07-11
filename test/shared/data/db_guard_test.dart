import 'package:checks/checks.dart';
import 'package:eigen_engine/core/errors/engine_exception.dart';
import 'package:eigen_engine/shared/data/db_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('dbGuard', () {
    test('returns the call result unchanged on success', () async {
      check(await dbGuard(() async => 42)).equals(42);
    });

    test('rethrows PostgrestException as EngineException with the code',
        () async {
      await check(
        dbGuard<void>(
          () => throw const PostgrestException(
            message: 'Game is full',
            code: EngineErrorCodes.gameFull,
          ),
        ),
      ).throws<EngineException>((thrown) {
        thrown.has((e) => e.message, 'message').equals('Game is full');
        thrown.has((e) => e.code, 'code').equals(EngineErrorCodes.gameFull);
      });
    });

    test('preserves a codeless PostgrestException as codeless', () async {
      await check(
        dbGuard<void>(() => throw const PostgrestException(message: 'boom')),
      ).throws<EngineException>(
        (thrown) => thrown.has((e) => e.code, 'code').isNull(),
      );
    });

    test('passes other exceptions through untouched', () async {
      await check(
        dbGuard<void>(() => throw StateError('not a server response')),
      ).throws<StateError>();
    });
  });
}
