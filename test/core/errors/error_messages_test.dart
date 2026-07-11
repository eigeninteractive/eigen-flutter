import 'package:checks/checks.dart';
import 'package:eigen_engine/core/errors/engine_exception.dart';
import 'package:eigen_engine/core/errors/error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('humanize', () {
    test('maps engine codes on EngineException to friendly copy', () {
      check(
        humanize(
          const EngineException(
            'Not your turn',
            code: EngineErrorCodes.notYourTurn,
          ),
        ),
      ).equals("It's not your turn.");
      check(
        humanize(
          const EngineException(
            'Stale state: expected version 3, current 4',
            code: EngineErrorCodes.staleVersion,
          ),
        ),
      ).equals('The game updated — try again.');
    });

    test('maps codes from client-direct RPC failures (via dbGuard)', () {
      // dbGuard rethrows PostgrestException as EngineException, so RPC
      // failures arrive here already carrying their EIGxx / SQLSTATE code.
      check(
        humanize(
          const EngineException(
            'Game is full',
            code: EngineErrorCodes.gameFull,
          ),
        ),
      ).equals('This game is already full.');
      check(
        humanize(
          const EngineException(
            'duplicate key value violates unique constraint',
            code: '23505',
          ),
        ),
      ).equals('That seat just filled up.');
    });

    test('dispatches on code, not message text', () {
      // The server copy can change freely — only the code decides.
      check(
        humanize(
          const EngineException(
            'reworded server copy',
            code: EngineErrorCodes.usernameTaken,
          ),
        ),
      ).equals('That username is already taken.');
      check(
        humanize(const EngineException('Not your turn')),
      ).equals('Something went wrong. Please try again.');
    });

    test('maps network errors by exception shape', () {
      check(
        humanize(Exception('SocketException: failed host lookup')),
      ).equals("Can't reach the server. Check your connection.");
    });

    test('falls back for unrecognised errors', () {
      check(
        humanize(Exception('totally unexpected')),
      ).equals('Something went wrong. Please try again.');
    });
  });
}
