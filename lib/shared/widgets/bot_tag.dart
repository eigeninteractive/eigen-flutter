import 'package:flutter/material.dart';

/// Compact pill that labels a participant as a bot.
///
/// The single inline "is a bot" label, used wherever there's room for text
/// (player lists, profile header). For label-less contexts — e.g. small
/// overlapping avatar stacks — use the corner badge on [PlayerAvatar] instead.
class BotTag extends StatelessWidget {
  const BotTag({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 12,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 3),
          Text(
            'Bot',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
