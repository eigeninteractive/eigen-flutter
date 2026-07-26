import 'package:eigen_api/eigen_api.dart';
import 'package:flutter/material.dart';

/// UI helpers for [GameStatus] — color and icon mappings.
extension GameStatusUI on GameStatus {
  /// Returns the color associated with this status from [colorScheme].
  Color color(ColorScheme colorScheme) => switch (this) {
    GameStatus.waiting => colorScheme.tertiary,
    GameStatus.ready => colorScheme.secondary,
    GameStatus.active => colorScheme.primary,
    GameStatus.finished => colorScheme.outline,
    GameStatus.aborted => colorScheme.error,
    GameStatus.unknownDefaultOpenApi => colorScheme.outline,
  };

  /// Returns the icon associated with this status.
  IconData get icon => switch (this) {
    GameStatus.waiting => Icons.hourglass_empty,
    GameStatus.ready => Icons.play_circle_outline,
    GameStatus.active => Icons.sports_esports,
    GameStatus.finished => Icons.emoji_events,
    GameStatus.aborted => Icons.cancel_outlined,
    GameStatus.unknownDefaultOpenApi => Icons.help_outline,
  };
}

/// UI helpers for [OutcomeResultEnum] — icon, color, and label mappings.
///
/// Defined on the nullable type so the null case (aborted game, no outcome
/// row written) can be handled uniformly alongside real results.
extension OutcomeResultUI on OutcomeResultEnum? {
  /// Returns the icon associated with this result.
  IconData get icon => switch (this) {
    OutcomeResultEnum.win => Icons.emoji_events,
    OutcomeResultEnum.loss => Icons.close,
    OutcomeResultEnum.draw => Icons.handshake_outlined,
    OutcomeResultEnum.eliminated => Icons.remove_circle_outline,
    OutcomeResultEnum.unknownDefaultOpenApi => Icons.help_outline,
    null => Icons.cancel_outlined,
  };

  /// Returns the color associated with this result from [colorScheme].
  Color color(ColorScheme colorScheme) => switch (this) {
    OutcomeResultEnum.win => colorScheme.primary,
    OutcomeResultEnum.loss => colorScheme.error,
    OutcomeResultEnum.draw => colorScheme.tertiary,
    OutcomeResultEnum.eliminated => colorScheme.error,
    OutcomeResultEnum.unknownDefaultOpenApi => colorScheme.outline,
    null => colorScheme.outline,
  };

  /// Returns the short display label for this result.
  String get label => switch (this) {
    OutcomeResultEnum.win => 'Won',
    OutcomeResultEnum.loss => 'Lost',
    OutcomeResultEnum.draw => 'Draw',
    OutcomeResultEnum.eliminated => 'Eliminated',
    OutcomeResultEnum.unknownDefaultOpenApi => 'Unknown',
    null => 'Aborted',
  };
}
