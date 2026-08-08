import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_flutter/core/connectivity/connectivity_provider.dart';
import 'package:eigen_flutter/core/game/timing_constants.dart';
import 'package:eigen_flutter/features/game/presentation/widgets/timer_builders.dart';
import 'package:eigen_flutter/core/api/engine_api_providers.dart';

/// Shows all players' remaining time banks side by side for budget
/// (accumulated clock) games.
///
/// Each cell is independently computed via [PlayerTimerBuilder], so only
/// the cell whose value changed triggers a rebuild. Inactive players'
/// banks are static until the next observation arrives.
/// Any bank below 60 seconds turns [ColorScheme.error].
///
/// The clock stays truthful (unlike the per-action countdown, it is not pulled
/// earlier by a soft margin; that would make a chess-style clock snap back up
/// on submit). Instead, the local player's own cell shows a "Submit!" cue once
/// their remaining bank drops into the final-headroom zone
/// ([softDeadlineMarginFor]), nudging them to commit before latency carries the
/// move past the deadline. The server grace window does the actual protecting.
///
/// When offline all cells freeze at their last known values and the active
/// cell renders as inactive so it doesn't falsely suggest time is draining.
class BudgetClock extends ConsumerWidget {
  const BudgetClock({
    super.key,
    required this.playerTimes,
    required this.deadline,
    required this.pendingPlayers,
    required this.myPlayerIndex,
  });

  /// Remaining time in milliseconds per player, 0-indexed.
  final List<int> playerTimes;

  /// Absolute server deadline for the acting seat's bank, epoch milliseconds.
  /// Null in an untimed phase.
  final int? deadline;

  /// Indices of currently active (draining) players.
  final List<int> pendingPlayers;

  /// This client's player index; their cell is labelled "You".
  final int myPlayerIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        for (int i = 0; i < playerTimes.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: PlayerTimerBuilder(
              playerTimes: playerTimes,
              deadline: deadline == null
                  ? null
                  : ref.watch(serverClockProvider).deviceTimeFor(deadline!),
              pendingPlayers: pendingPlayers,
              playerIndex: i,
              isPaused: isOffline,
              builder: (context, remainingMs, isActive) {
                final isMine = i == myPlayerIndex;
                // Final-headroom zone for my own active cell: capped to a
                // fraction of the bank so a tiny bank doesn't sit permanently
                // in the cue.
                final softMarginMs = softDeadlineMarginFor(
                  Duration(milliseconds: playerTimes[i]),
                ).inMilliseconds;
                return _ClockCell(
                  remainingMs: remainingMs,
                  label: isMine ? 'You' : 'P${i + 1}',
                  // Treat active cell as inactive when offline so the pulsing
                  // border and drain colour don't suggest time is running.
                  isActive: isActive && !isOffline,
                  isSubmitZone:
                      isMine &&
                      isActive &&
                      !isOffline &&
                      remainingMs <= softMarginMs,
                  colorScheme: colorScheme,
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _ClockCell extends StatelessWidget {
  const _ClockCell({
    required this.remainingMs,
    required this.label,
    required this.isActive,
    required this.isSubmitZone,
    required this.colorScheme,
  });

  final int remainingMs;
  final String label;
  final bool isActive;

  /// True for the local player's active cell once it drops into the final
  /// headroom before the deadline, shows a "Submit!" nudge.
  final bool isSubmitZone;
  final ColorScheme colorScheme;

  bool get _isUrgent => remainingMs < 60000;

  Color get _timeColor {
    if (_isUrgent) return colorScheme.error;
    if (isActive) return colorScheme.primary;
    return colorScheme.onSurfaceVariant;
  }

  Color get _bgColor {
    if (_isUrgent && isActive) {
      return colorScheme.errorContainer.withValues(alpha: 0.3);
    }
    if (isActive) return colorScheme.primaryContainer.withValues(alpha: 0.3);
    return colorScheme.surfaceContainerHighest;
  }

  String get _formatted {
    final totalSeconds = remainingMs ~/ 1000;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(8),
        border: isActive
            ? Border.all(
                color: _isUrgent
                    ? colorScheme.error.withValues(alpha: 0.5)
                    : colorScheme.primary.withValues(alpha: 0.5),
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isSubmitZone ? 'Submit!' : label,
            style: textTheme.labelSmall?.copyWith(
              color: isActive
                  ? (_isUrgent ? colorScheme.error : colorScheme.primary)
                  : colorScheme.onSurfaceVariant,
              fontWeight: isSubmitZone ? FontWeight.bold : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatted,
            style: textTheme.titleMedium?.copyWith(color: _timeColor),
          ),
        ],
      ),
    );
  }
}
