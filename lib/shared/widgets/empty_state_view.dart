import 'package:flutter/material.dart';

/// Generic illustrated empty state for list screens.
///
/// Renders an icon inside a [ColorScheme.primaryContainer] circle, a bold
/// [headline], a subdued [message] body, and an optional [FilledButton] CTA.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.cta,
    this.onCta,
    this.tonalCta = false,
  }) : assert(
         cta == null || onCta != null,
         'onCta must be provided when cta is set',
       );

  final IconData icon;
  final String title;
  final String message;

  /// Label for the call-to-action button. Omit for no button.
  final String? cta;

  /// Handler for the CTA button. Required when [cta] is provided.
  final VoidCallback? onCta;

  /// When true, renders a [FilledButton.tonal] instead of [FilledButton].
  /// Use for soft suggestions (nudges) rather than primary actions.
  final bool tonalCta;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (cta != null && onCta != null) ...[
              const SizedBox(height: 24),
              if (tonalCta)
                FilledButton.tonal(onPressed: onCta, child: Text(cta!))
              else
                FilledButton(onPressed: onCta, child: Text(cta!)),
            ],
          ],
        ),
      ),
    );
  }
}
