import 'package:flutter/material.dart';

/// Compact pill that labels a player as an anonymous guest.
///
/// Sibling of `BotTag`: the single inline "is a guest" label, used wherever
/// there's room for text (profile header, player lists). Guests are throwaway
/// accounts — they cannot be friended, so UI showing this tag typically also
/// hides social affordances.
class GuestTag extends StatelessWidget {
  const GuestTag({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_outline,
            size: 12,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 3),
          Text(
            'Guest',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
