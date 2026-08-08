import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/errors/engine_exception.dart';
import 'package:json_annotation/json_annotation.dart';

/// Runs a generated API call, rethrowing a server-reported failure as the
/// domain [EngineException] so nothing above the data layer handles Dio types.
///
/// Only failures that carried a response are converted: those are the server
/// answering `{ error, code? }`, and the stable `code` survives onto
/// [EngineException.code] for callers and `humanize` to dispatch on. A failure
/// with no response (connection refused, DNS, timeout, a cancelled request)
/// propagates untouched, preserving the distinction between "the server said
/// no" and "the outcome is unknown". That difference matters for a
/// state-changing command: a rejected move did not happen, whereas a timed-out
/// one may well have landed.
///
/// Wrap every generated call at the data layer:
///
/// ```dart
/// final lobby = await engineCall(() => api.getLobby(limit: 50));
/// ```
Future<T> engineCall<T>(Future<T> Function() run) async {
  try {
    return await run();
  } on DioException catch (e) {
    final response = e.response;
    if (response == null) rethrow;
    throw _engineExceptionFrom(response);
  }
}

/// Runs a generated API call and returns its decoded body, unwrapping the
/// [Response].
///
/// The successor to the `final response = await engineCall(...); return
/// response.data?.x ?? ...` shape that recurred at every read site: it runs
/// through [engineCall], so a server-reported failure still surfaces as an
/// [EngineException] and a transport failure still propagates untouched, then
/// returns the non-null payload.
///
/// ```dart
/// final friends = (await engineData(() => api.listFriends())).friends;
/// ```
///
/// Throws [EngineException] if a success response carries no body, which is a
/// contract violation for an endpoint declared to return one (never the normal
/// path: the generated models make list fields non-null, so a present body
/// needs no `?? const []`). A call that expects no body, such as a 204 write, uses
/// [engineCall] directly instead.
Future<T> engineData<T>(Future<Response<T>> Function() run) async {
  final response = await engineCall(run);
  final data = response.data;
  if (data == null) {
    throw const EngineException('The server returned an empty response.');
  }
  return data;
}

/// Reads the `{ error, code? }` envelope out of a failed response.
///
/// Falls back to a status-line message when the body is missing, is not the
/// envelope at all (a proxy's HTML error page, or a failure raised before the
/// engine's own handler ran), or fails to parse.
///
/// Unknown enum values decode to [ErrorCode.unknownDefaultOpenApi], so a client
/// one release behind the server still preserves the server's message and
/// reaches the generic UI fallback. The parse remains guarded for malformed
/// envelopes: those degrade to the status line, and the caller gets an
/// [EngineException] with a null [EngineException.code].
EngineException _engineExceptionFrom(Response<dynamic> response) {
  final data = response.data;
  if (data is Map) {
    try {
      final parsed = ErrorResponse.fromJson(Map<String, dynamic>.from(data));
      if (parsed.code == ErrorCode.unknownDefaultOpenApi) {
        developer.log(
          'Unknown ErrorCode received: ${data['code']}',
          name: 'eigen.compatibility',
        );
      }
      return EngineException(parsed.error, code: parsed.code);
    } on CheckedFromJsonException catch (_) {
      // Fall through to the status line.
    }
  }
  return EngineException('Request failed (status ${response.statusCode})');
}
