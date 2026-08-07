import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';

/// The linked span inside the default credit, and where it goes. Kept in step
/// with the engine's `CREDIT_BRAND`/`CREDIT_URL`, so the app and the game's own
/// website end on the same line rendered the same way.
const _creditBrand = 'EigenInteractive';
final _creditUrl = Uri.parse('https://eigeninteractive.com');

/// The credit line at the foot of the settings and about screens.
///
/// Only the brand name inside the line is tappable, marked by colour rather
/// than an underline — the sentence around it is prose and does not point
/// anywhere. A custom [Branding.madeByCredit] that never mentions the engine
/// renders as plain text, so an app that replaced the line does not silently
/// link its own words to us.
///
/// Stateful only to own the recognizer: a [TapGestureRecognizer] holds
/// resources and must be disposed, which a build method cannot do.
class MadeByCredit extends ConsumerStatefulWidget {
  const MadeByCredit({super.key});

  @override
  ConsumerState<MadeByCredit> createState() => _MadeByCreditState();
}

class _MadeByCreditState extends ConsumerState<MadeByCredit> {
  late final TapGestureRecognizer _tap = TapGestureRecognizer()
    ..onTap = () => launchUrl(_creditUrl, mode: LaunchMode.externalApplication);

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credit = ref.watch(appConfigProvider).branding.madeByCredit;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final at = credit.indexOf(_creditBrand);
    // The default line ends on the brand, so the trailing part is usually
    // empty. Both are dropped when empty rather than shipping spans with
    // nothing in them.
    final before = at == -1 ? '' : credit.substring(0, at);
    final after = at == -1 ? '' : credit.substring(at + _creditBrand.length);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: at == -1
          ? Text(credit, style: style, textAlign: TextAlign.center)
          : Text.rich(
              TextSpan(
                style: style,
                children: [
                  if (before.isNotEmpty) TextSpan(text: before),
                  TextSpan(
                    text: _creditBrand,
                    style: TextStyle(color: theme.colorScheme.primary),
                    recognizer: _tap,
                  ),
                  if (after.isNotEmpty) TextSpan(text: after),
                ],
              ),
              textAlign: TextAlign.center,
            ),
    );
  }
}
