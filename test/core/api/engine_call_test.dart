import 'package:checks/checks.dart';
import 'package:dio/dio.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/engine_call.dart';
import 'package:eigen_flutter/core/errors/engine_exception.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [DioException] as Dio raises it for a non-2xx response.
DioException _serverSaidNo(int status, Object? body) {
  final options = RequestOptions(path: '/api/engine/games');
  return DioException.badResponse(
    statusCode: status,
    requestOptions: options,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: body,
    ),
  );
}

/// A [DioException] with no response: the wire never answered.
DioException _noAnswer(DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: '/api/engine/games'),
  type: type,
);

/// A 2xx [Response] carrying [body] (possibly null, as Dio returns for an
/// empty body).
Response<T> _ok<T>(T? body) {
  final options = RequestOptions(path: '/api/engine/games');
  return Response<T>(requestOptions: options, statusCode: 200, data: body);
}

void main() {
  group('a server-reported failure', () {
    test('becomes an EngineException carrying the typed code', () async {
      await check(
        engineCall<void>(
          () => throw _serverSaidNo(409, {
            'error': 'Game is full',
            'code': 'gameFull',
          }),
        ),
      ).throws<EngineException>(
        (e) => e
          ..has((x) => x.code, 'code').equals(ErrorCode.gameFull)
          ..has((x) => x.message, 'message').equals('Game is full'),
      );
    });

    test('carries a null code when the body has none', () async {
      await check(
        engineCall<void>(
          () => throw _serverSaidNo(400, {'error': 'Invalid request'}),
        ),
      ).throws<EngineException>((e) => e.has((x) => x.code, 'code').isNull());
    });

    test('degrades to the status line for a non-envelope body', () async {
      // A proxy's HTML error page, or anything raised before the engine's own
      // handler ran.
      await check(
        engineCall<void>(
          () => throw _serverSaidNo(502, '<html>bad gateway</html>'),
        ),
      ).throws<EngineException>((e) => e.has((x) => x.code, 'code').isNull());
    });

    test('preserves an unrecognised code as the sentinel', () async {
      // What a client one release behind a newer server sees. The message and
      // coded-failure path survive even before this build knows the meaning.
      await check(
        engineCall<void>(
          () => throw _serverSaidNo(409, {
            'error': 'Something new',
            'code': 'a_code_from_the_future',
          }),
        ),
      ).throws<EngineException>(
        (e) => e
          ..has((x) => x.message, 'message').equals('Something new')
          ..has((x) => x.code, 'code').equals(ErrorCode.unknownDefaultOpenApi),
      );
    });
  });

  group('a transport failure', () {
    // These must stay DioExceptions: a rejected command definitively did not
    // happen, whereas a timed-out one may well have landed. Collapsing the two
    // would make that undecidable for the caller.
    for (final type in [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.cancel,
    ]) {
      test('propagates untouched ($type)', () async {
        await check(
          engineCall<void>(() => throw _noAnswer(type)),
        ).throws<DioException>();
      });
    }
  });

  test('a successful call returns its value', () async {
    await check(engineCall(() async => 42)).completes((v) => v.equals(42));
  });

  group('engineData', () {
    test('unwraps the response body', () async {
      await check(
        engineData(() async => _ok('hello')),
      ).completes((v) => v.equals('hello'));
    });

    test('throws EngineException when a success carries no body', () async {
      await check(
        engineData<String>(() async => _ok<String>(null)),
      ).throws<EngineException>((e) => e.has((x) => x.code, 'code').isNull());
    });

    test('still surfaces a server failure as an EngineException', () async {
      await check(
        engineData<String>(
          () => throw _serverSaidNo(409, {
            'error': 'Game is full',
            'code': 'gameFull',
          }),
        ),
      ).throws<EngineException>(
        (e) => e.has((x) => x.code, 'code').equals(ErrorCode.gameFull),
      );
    });

    test('still lets a transport failure propagate untouched', () async {
      await check(
        engineData<String>(
          () => throw _noAnswer(DioExceptionType.connectionError),
        ),
      ).throws<DioException>();
    });
  });
}
