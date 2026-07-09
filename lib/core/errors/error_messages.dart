import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_engine/core/errors/engine_exception.dart';

/// Converts a raw exception into a human-readable message suitable for display
/// in snackbars.
///
/// Structured engine errors dispatch on their stable code
/// ([EngineErrorCodes], carried by [EngineException] for edge-function routes
/// and [PostgrestException.code] for client-direct RPCs) — copy edits on the
/// server can never change which message the user sees. Everything without a
/// code is either a transport failure (detected by exception shape) or an
/// unexpected error, which gets the generic message; there is deliberately no
/// message-text matching.
String humanize(Object e) {
  final code = switch (e) {
    EngineException(:final code) => code,
    PostgrestException(:final code) => code,
    _ => null,
  };
  final coded = _messageForCode(code);
  if (coded != null) return coded;

  if (_isNetworkError(e.toString())) {
    return "Can't reach the server. Check your connection.";
  }
  return 'Something went wrong. Please try again.';
}

/// Friendly copy for a stable engine error code, or null when the code is
/// unknown. `23505` is Postgres's unique-violation SQLSTATE — the seat-insert
/// race on a filling game.
String? _messageForCode(String? code) => switch (code) {
  EngineErrorCodes.staleVersion ||
  EngineErrorCodes.ratingConflict => 'The game updated — try again.',
  EngineErrorCodes.notYourTurn => "It's not your turn.",
  EngineErrorCodes.turnExpired => 'Time ran out for this turn.',
  EngineErrorCodes.gameNotActive => 'This game has already ended.',
  EngineErrorCodes.gameNotFound =>
    'Game not found. Check the code and try again.',
  EngineErrorCodes.notParticipant => "You're not in this game.",
  EngineErrorCodes.gameFull => 'This game is already full.',
  EngineErrorCodes.alreadyJoined => "You're already in this game.",
  EngineErrorCodes.notAcceptingPlayers => 'This game has already started.',
  EngineErrorCodes.friendsOnly =>
    'Only friends of the host can join this game.',
  EngineErrorCodes.unsupportedSchema => 'Update your app to join this game.',
  EngineErrorCodes.usernameInvalid =>
    'Usernames are 3-20 letters, numbers, dots, or underscores.',
  EngineErrorCodes.usernameTaken => 'That username is already taken.',
  EngineErrorCodes.notAuthenticated => 'Please sign in again.',
  EngineErrorCodes.illegalMove => "That move isn't allowed.",
  '23505' => 'That seat just filled up.',
  _ => null,
};

bool _isNetworkError(String message) =>
    message.contains('SocketException') ||
    message.contains('Failed host lookup') ||
    message.contains('Network request failed') ||
    message.contains('Connection refused') ||
    message.contains('XMLHttpRequest error') ||
    message.contains('network_error') ||
    message.contains('Unable to connect');
