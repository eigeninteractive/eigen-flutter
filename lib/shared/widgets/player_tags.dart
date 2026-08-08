/// Inline pills labelling a player's kind (bot, guest).
///
/// The single inline label for each kind, used wherever there's room for
/// text (player lists, profile header). For label-less contexts, e.g. small
/// overlapping avatar stacks, use the corner badge on [PlayerAvatar] instead.
library;

import 'package:flutter/material.dart';

/// Shared shell for the player-kind pills. Geometry and typography live only
/// here so the tags cannot drift apart visually.
class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w600,
    );
    // The icon tracks the label size so the pill scales as one unit if the
    // theme's labelSmall changes.
    final iconSize = (style?.fontSize ?? 11) + 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: foreground),
          const SizedBox(width: 3),
          Text(label, style: style),
        ],
      ),
    );
  }
}

/// Compact pill that labels a participant as a bot.
class BotTag extends StatelessWidget {
  const BotTag({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _TagPill(
      icon: Icons.smart_toy_outlined,
      label: 'Bot',
      background: colorScheme.secondaryContainer,
      foreground: colorScheme.onSecondaryContainer,
    );
  }
}

/// Compact pill that labels a player as an anonymous guest.
///
/// Guests are throwaway accounts; they cannot be friended, so UI showing
/// this tag typically also hides social affordances.
class GuestTag extends StatelessWidget {
  const GuestTag({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _TagPill(
      icon: Icons.person_outline,
      label: 'Guest',
      background: colorScheme.surfaceContainerHighest,
      foreground: colorScheme.onSurfaceVariant,
    );
  }
}
