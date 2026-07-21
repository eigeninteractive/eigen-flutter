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
/// with no response — connection refused, DNS, timeout, a cancelled request —
/// propagates untouched, preserving the distinction between "the server said
/// no" and "the outcome is unknown". That difference matters for a
/// state-changing command: a rejected move did not happen, whereas a timed-out
/// one may well have landed.
///
/// The direct successor to the Supabase-era `dbGuard`, and used the same way:
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

/// Reads the `{ error, code? }` envelope out of a failed response.
///
/// Falls back to a status-line message when the body is missing, is not the
/// envelope at all (a proxy's HTML error page, or a failure raised before the
/// engine's own handler ran), or fails to parse.
///
/// The parse is guarded because the generated model is strict: it rejects an
/// unrecognised `code`, which is exactly what a client one release behind the
/// server would see. Throwing there would replace a clean "the server said no"
/// with an opaque parse crash on the failure path — so an unreadable envelope
/// degrades to the status line instead, and the caller still gets an
/// [EngineException] with a null [EngineException.code].
EngineException _engineExceptionFrom(Response<dynamic> response) {
  final data = response.data;
  if (data is Map) {
    try {
      final parsed = ErrorResponse.fromJson(Map<String, dynamic>.from(data));
      return EngineException(parsed.error, code: parsed.code);
    } on CheckedFromJsonException catch (_) {
      // Fall through to the status line.
    }
  }
  return EngineException('Request failed (status ${response.statusCode})');
}
