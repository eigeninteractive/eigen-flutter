import 'package:eigen_api/eigen_api.dart';

/// A failure the engine server itself reported: a non-2xx response carrying
/// the `{ error, code? }` envelope.
///
/// Distinct from a transport failure (no response at all), which propagates as
/// the underlying `DioException` so callers can tell "the server said no" from
/// "the outcome is unknown". `engineCall` draws that line.
///
/// Dispatch on [code], never on [message]: the message is display copy the
/// server may reword at any time, while the code is a stable machine value.
class EngineException implements Exception {
  const EngineException(this.message, {this.code});

  /// The server's human-readable text. Used as display copy only when [code] is
  /// null; a coded failure is phrased by `humanize` instead.
  final String message;

  /// The stable machine code, or null for failures that carry none: request
  /// validation and unexpected 500s.
  ///
  /// Values introduced by a newer server decode to
  /// [ErrorCode.unknownDefaultOpenApi], preserving the coded-failure path until
  /// this app learns their specific meaning.
  final ErrorCode? code;

  @override
  String toString() => message;
}
