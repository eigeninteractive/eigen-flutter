import 'package:checks/checks.dart';
import 'package:dio/dio.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/errors/engine_exception.dart';
import 'package:eigen_flutter/core/errors/error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('humanize', () {
    test('maps engine codes to friendly copy', () {
      check(
        humanize(
          const EngineException('Not pending', code: ErrorCode.notPending),
        ),
      ).equals("It's not your turn.");
      check(
        humanize(
          const EngineException(
            'Stale state: expected version 3, current 4',
            code: ErrorCode.stateUpdated,
          ),
        ),
      ).equals('The game updated. Try again.');
      check(
        humanize(
          const EngineException('slow down', code: ErrorCode.rateLimited),
        ),
      ).equals("You're doing that too quickly. Wait a moment and try again.");
    });

    test('dispatches on code, not message text', () {
      // The server copy can change freely; only the code decides.
      check(
        humanize(
          const EngineException(
            'reworded server copy',
            code: ErrorCode.usernameTaken,
          ),
        ),
      ).equals('That username is already taken.');
    });

    test('gives every known code its own copy', () {
      // The generated sentinel deliberately shares generic copy. Published
      // server codes remain unique so specific guidance cannot regress to a
      // copy-pasted message unnoticed.
      final knownCodes = ErrorCode.values.where(
        (code) => code != ErrorCode.unknownDefaultOpenApi,
      );
      final messages = knownCodes.map(messageForCode).toSet();
      check(messages).length.equals(knownCodes.length);
    });

    test('falls back to generic copy for a code from a newer server', () {
      check(
        humanize(
          const EngineException(
            'A newer server rejection',
            code: ErrorCode.unknownDefaultOpenApi,
          ),
        ),
      ).equals('Something went wrong. Please try again.');
    });

    test('falls back to the generic message for an uncoded failure', () {
      // Validation details and unexpected 500s: the server's own wording is
      // diagnostic, sometimes internal, and never shown.
      check(
        humanize(const EngineException('engine bug: expected a roster')),
      ).equals('Something went wrong. Please try again.');
    });

    test('reports a transport failure as an offline message', () {
      // By exception type, not by matching message text.
      check(
        humanize(
          DioException(
            requestOptions: RequestOptions(path: '/api/engine/lobby'),
            type: DioExceptionType.connectionError,
          ),
        ),
      ).equals("Can't reach the server. Check your connection.");
    });

    test('falls back for unrecognised errors', () {
      check(
        humanize(Exception('totally unexpected')),
      ).equals('Something went wrong. Please try again.');
    });
  });
}
