import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_flutter/core/api/engine_api_providers.dart';
import 'package:eigen_flutter/core/connectivity/connectivity_provider.dart';
import 'package:eigen_flutter/core/game/timing_constants.dart';
import 'package:eigen_flutter/features/game/presentation/widgets/timer_builders.dart';

/// Styled countdown toward [deadline].
///
/// Shows remaining time as "12m 34s" or "45s". Turns [ColorScheme.error]
/// when under 60 seconds. Returns an empty widget once the deadline has
/// passed.
///
/// When the device is offline the countdown freezes at the last known value
/// and renders with a pause icon in [ColorScheme.onSurfaceVariant] so the
/// player knows the timer is not draining locally (though the server clock
/// continues).
///
/// Provide [style] to override the default [TextTheme.bodySmall], useful
/// when the countdown should be larger (e.g. inside the game screen).
///
/// [deadline] is an absolute server timestamp in epoch milliseconds, converted
/// here against [ServerClock]; a device with a skewed clock would otherwise
/// show a countdown that disagrees with when the turn actually expires.
///
/// Provide [windowMillis] (how long the turn was when it began) to enable the
/// soft-deadline margin: the countdown reaches zero slightly before the true
/// deadline so an on-time submit survives network latency. The margin is capped
/// to a fraction of the window so a short one, a three-second reaction window,
/// is not swallowed whole. Omit it (e.g. on at-a-glance home cards) for a
/// truthful, unmargined countdown.
///
/// Timing state is owned by [TurnTimerBuilder].
class TurnCountdown extends ConsumerWidget {
  const TurnCountdown({
    super.key,
    required this.deadline,
    this.windowMillis,
    this.style,
  });

  /// Absolute server deadline, epoch milliseconds.
  final int deadline;

  /// How long this turn was when it started, in milliseconds.
  final int? windowMillis;

  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final window = windowMillis;
    final softMargin = window == null
        ? Duration.zero
        : softDeadlineMarginFor(Duration(milliseconds: window));

    return TurnTimerBuilder(
      deadline: ref.watch(serverClockProvider).deviceTimeFor(deadline),
      softMargin: softMargin,
      isPaused: isOffline,
      builder: (context, remaining) {
        if (remaining == Duration.zero) return const SizedBox.shrink();
        final isUrgent = !isOffline && remaining.inSeconds < 60;
        final mm = remaining.inMinutes;
        final ss = remaining.inSeconds % 60;
        final label = mm > 0 ? '${mm}m ${ss}s' : '${ss}s';
        final color = isOffline
            ? colorScheme.onSurfaceVariant
            : isUrgent
            ? colorScheme.error
            : colorScheme.primary;
        final baseStyle = (style ?? Theme.of(context).textTheme.bodySmall)
            ?.copyWith(color: color, fontWeight: FontWeight.bold);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOffline) ...[
              Icon(
                Icons.pause_rounded,
                size: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 3),
            ],
            Text(label, style: baseStyle),
          ],
        );
      },
    );
  }
}
