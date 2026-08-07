import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:eigen_flutter/shared/widgets/made_by_credit.dart';

/// The line as the app ships it, and as the game's own website renders it.
AppConfig _config(String credit) => AppConfig(
  branding: Branding(appName: 'Test App', madeByCredit: credit),
  engine: const EngineConfig(
    apiBaseUrl: 'https://example.test',
    googleWebClientId: 'client',
    firebaseVapidKey: 'test-vapid-key',
  ),
);

/// The spans of the rendered line, paired with whether each is tappable.
List<(String, bool)> _spans(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text));
  final spans = <(String, bool)>[];
  text.textSpan?.visitChildren((span) {
    if (span is TextSpan && span.text != null) {
      spans.add((span.text!, span.recognizer is TapGestureRecognizer));
    }
    return true;
  });
  return spans;
}

Future<void> _pump(WidgetTester tester, String credit) => tester.pumpWidget(
  ProviderScope(
    overrides: [appConfigProvider.overrideWithValue(_config(credit))],
    child: const MaterialApp(home: Scaffold(body: MadeByCredit())),
  ),
);

void main() {
  testWidgets('links the brand inside the line and nothing else', (
    tester,
  ) async {
    await _pump(tester, 'Built with EigenInteractive');

    // "Build with" is prose and points nowhere; only the name is tappable.
    expect(_spans(tester), [
      ('Built with ', false),
      ('EigenInteractive', true),
    ]);
  });

  testWidgets('marks the link by colour rather than an underline', (
    tester,
  ) async {
    await _pump(tester, 'Built with EigenInteractive');

    final context = tester.element(find.byType(MadeByCredit));
    final primary = Theme.of(context).colorScheme.primary;
    final text = tester.widget<Text>(find.byType(Text));
    final brand = (text.textSpan! as TextSpan).children![1] as TextSpan;
    expect(brand.style?.color, primary);
    expect(brand.style?.decoration, isNot(TextDecoration.underline));
  });

  testWidgets('leaves a credit that never names the engine as plain text', (
    tester,
  ) async {
    // Otherwise an app that replaced the line entirely would have its own
    // words silently linked to us.
    await _pump(tester, 'Made by tester');

    expect(find.text('Made by tester'), findsOneWidget);
    expect(_spans(tester), isEmpty);
  });
}
