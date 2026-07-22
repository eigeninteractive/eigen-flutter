import 'package:flutter/material.dart';
import 'package:eigen_api/eigen_api.dart';

/// Returns the icon that best represents a game's timing mode.
IconData gameTimingIcon(GameSummary game) {
  if (game.budgetSeconds != null) return Icons.av_timer;
  final t = game.turnSeconds;
  if (t == null) return Icons.all_inclusive;
  if (t <= 60) return Icons.flash_on;
  if (t <= 600) return Icons.speed;
  return Icons.schedule;
}

/// Returns a human-readable timing label for a game.
///
/// Examples: "untimed", "30s/turn", "5m/turn", "3m+2s", "10m+5s".
String gameTimingLabel(GameSummary game) {
  if (game.budgetSeconds != null) {
    final budget = _formatSeconds(game.budgetSeconds!);
    final inc = game.incrementSeconds;
    return inc != null && inc > 0 ? '$budget+${inc}s' : budget;
  }
  final t = game.turnSeconds;
  if (t == null) return 'untimed';
  if (t < 60) return '${t}s/turn';
  if (t < 3600) return '${t ~/ 60}m/turn';
  if (t < 86400) return '${t ~/ 3600}h/turn';
  return '${t ~/ 86400}d/turn';
}

String _formatSeconds(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m';
  return '${seconds ~/ 3600}h';
}

/// Returns a compact label for how long a game has been waiting.
///
/// [createdAt] is epoch milliseconds, as every timestamp on the wire is.
///
/// Examples: "just now", "5m waiting", "2h waiting".
String formatWaitDuration(int createdAt) {
  final elapsed = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(createdAt),
  );
  if (elapsed.inSeconds < 60) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m waiting';
  return '${elapsed.inHours}h waiting';
}
