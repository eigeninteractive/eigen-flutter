import 'package:flutter/material.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/core/game/game_status.dart';

/// UI helpers for [GameStatus] — color and icon mappings.
extension GameStatusUI on GameStatus {
  /// Returns the color associated with this status from [colorScheme].
  Color color(ColorScheme colorScheme) => switch (this) {
    GameStatus.waiting => colorScheme.tertiary,
    GameStatus.ready => colorScheme.secondary,
    GameStatus.active => colorScheme.primary,
    GameStatus.finished => colorScheme.outline,
    GameStatus.aborted => colorScheme.error,
  };

  /// Returns the icon associated with this status.
  IconData get icon => switch (this) {
    GameStatus.waiting => Icons.hourglass_empty,
    GameStatus.ready => Icons.play_circle_outline,
    GameStatus.active => Icons.sports_esports,
    GameStatus.finished => Icons.emoji_events,
    GameStatus.aborted => Icons.cancel_outlined,
  };
}

/// UI helpers for [OutcomeResult] — icon, color, and label mappings.
///
/// Defined on the nullable type so the null case (aborted game, no outcome
/// row written) can be handled uniformly alongside real results.
extension OutcomeResultUI on OutcomeResult? {
  /// Returns the icon associated with this result.
  IconData get icon => switch (this) {
    OutcomeResult.win => Icons.emoji_events,
    OutcomeResult.loss => Icons.close,
    OutcomeResult.draw => Icons.handshake_outlined,
    OutcomeResult.eliminated => Icons.remove_circle_outline,
    null => Icons.cancel_outlined,
  };

  /// Returns the color associated with this result from [colorScheme].
  Color color(ColorScheme colorScheme) => switch (this) {
    OutcomeResult.win => colorScheme.primary,
    OutcomeResult.loss => colorScheme.error,
    OutcomeResult.draw => colorScheme.tertiary,
    OutcomeResult.eliminated => colorScheme.error,
    null => colorScheme.outline,
  };

  /// Returns the short display label for this result.
  String get label => switch (this) {
    OutcomeResult.win => 'Won',
    OutcomeResult.loss => 'Lost',
    OutcomeResult.draw => 'Draw',
    OutcomeResult.eliminated => 'Eliminated',
    null => 'Aborted',
  };
}
