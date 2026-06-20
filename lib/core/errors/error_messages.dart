import 'package:supabase_flutter/supabase_flutter.dart';

/// Converts a raw exception into a human-readable message suitable for display
/// in snackbars.
///
/// Known server-raised messages (from the game RPCs) are mapped to friendly
/// copy; for [PostgrestException] the match runs against the bare server
/// message so surrounding noise can never produce a false positive. Anything
/// unrecognised falls back to a generic message.
String humanize(Object e) {
  final s = e is PostgrestException ? e.message : e.toString();
  if (s.contains('Stale state')) return 'The game updated — try again.';
  if (s.contains('Not your turn')) return "It's not your turn.";
  if (s.contains('Turn has expired')) return 'Time ran out for this turn.';
  if (s.contains('Game is full')) return 'This game is already full.';
  if (s.contains('Already joined this game')) {
    return "You're already in this game.";
  }
  if (s.contains('Game is not accepting players')) {
    return 'This game has already started.';
  }
  if (s.contains('Only friends of the creator')) {
    return 'Only friends of the host can join this game.';
  }
  if (s.contains('Game not found')) {
    return 'Game not found. Check the code and try again.';
  }
  if (s.contains('Unsupported game schema')) {
    return 'Update your app to join this game.';
  }
  if (s.contains('Game is not active')) return 'This game has already ended.';
  if (s.contains('Not a participant')) return "You're not in this game.";
  if (s.contains('Username already taken')) {
    return 'That username is already taken.';
  }
  if (s.contains('Username must be')) {
    return 'Usernames are 3-20 letters, numbers, dots, or underscores.';
  }
  if (s.contains('duplicate key')) return 'That seat just filled up.';
  if (s.contains('Not authenticated')) return 'Please sign in again.';
  if (_isNetworkError(s)) {
    return "Can't reach the server. Check your connection.";
  }
  return 'Something went wrong. Please try again.';
}

bool _isNetworkError(String message) =>
    message.contains('SocketException') ||
    message.contains('Failed host lookup') ||
    message.contains('Network request failed') ||
    message.contains('Connection refused') ||
    message.contains('XMLHttpRequest error') ||
    message.contains('network_error') ||
    message.contains('Unable to connect');
