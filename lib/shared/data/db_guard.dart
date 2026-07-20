import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_flutter/core/errors/engine_exception.dart';

/// Runs a PostgREST call, rethrowing [PostgrestException] as the domain
/// [EngineException] so nothing above the data layer handles Supabase types.
///
/// The stable code (`EIGxx` for `app_*` RPCs, a SQLSTATE like `23505` for
/// constraint violations) carries over onto [EngineException.code], matching
/// what the edge-function path already throws — callers and `humanize`
/// dispatch on one exception type regardless of transport. Anything that is
/// not a PostgREST server response (network failures, decode errors)
/// propagates untouched.
Future<T> dbGuard<T>(Future<T> Function() run) async {
  try {
    return await run();
  } on PostgrestException catch (e) {
    throw EngineException(e.message, code: e.code);
  }
}
