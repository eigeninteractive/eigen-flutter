import 'package:checks/checks.dart';
import 'package:dio/dio.dart';
import 'package:eigen_flutter/core/api/retry_policy.dart';
import 'package:eigen_flutter/core/errors/engine_exception.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _transport(String method, DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: '/api/engine/lobby', method: method),
  type: type,
);

DioException _withResponse(String method, int status) => DioException(
  requestOptions: RequestOptions(path: '/api/engine/lobby', method: method),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/engine/lobby', method: method),
    statusCode: status,
  ),
);

void main() {
  group('retryTransientGet (transport layer)', () {
    test('retries a GET whose failure carried no response', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        check(retryTransientGet(_transport('GET', type), 1)).equals(true);
      }
    });

    test('never retries a write, even on a transport failure', () {
      // A timed-out POST may have landed and the outcome is unknown, so it must
      // not be replayed.
      for (final method in ['POST', 'PUT', 'DELETE', 'PATCH']) {
        check(
          retryTransientGet(
            _transport(method, DioExceptionType.connectionError),
            1,
          ),
        ).equals(false);
      }
    });

    test('never retries a failure that carried a response', () {
      // The server answered: a decision, not a blip, even for a 5xx or a 429.
      check(retryTransientGet(_withResponse('GET', 500), 1)).equals(false);
      check(retryTransientGet(_withResponse('GET', 429), 1)).equals(false);
      check(retryTransientGet(_withResponse('GET', 404), 1)).equals(false);
    });

    test('does not retry non-transport error types', () {
      check(
        retryTransientGet(_transport('GET', DioExceptionType.cancel), 1),
      ).equals(false);
      check(
        retryTransientGet(_transport('GET', DioExceptionType.badResponse), 1),
      ).equals(false);
    });
  });

  group('engineProviderRetry (provider layer)', () {
    test('retries a transport failure with short exponential backoff', () {
      final err = _transport('GET', DioExceptionType.connectionError);
      check(
        engineProviderRetry(0, err),
      ).equals(const Duration(milliseconds: 200));
      check(
        engineProviderRetry(1, err),
      ).equals(const Duration(milliseconds: 400));
    });

    test('stops after two tries', () {
      final err = _transport('GET', DioExceptionType.connectionError);
      check(engineProviderRetry(2, err)).isNull();
      check(engineProviderRetry(5, err)).isNull();
    });

    test('never retries a server-reported failure', () {
      // The whole point: Riverpod's default would re-run these up to ten times.
      check(
        engineProviderRetry(0, const EngineException('nope', code: null)),
      ).isNull();
      check(engineProviderRetry(0, _withResponse('GET', 409))).isNull();
      check(engineProviderRetry(0, Exception('unexpected'))).isNull();
    });
  });
}
