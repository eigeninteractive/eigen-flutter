import 'package:checks/checks.dart';
import 'package:eigen_flutter/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps the guest session when account switching is declined', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showExistingAccountSwitchDialog(context);
            },
            child: const Text('Upgrade'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to your existing account?'), findsOneWidget);
    expect(find.textContaining('cannot be transferred'), findsOneWidget);
    await tester.tap(find.text('Keep playing as guest'));
    await tester.pumpAndSettle();

    check(result).equals(false);
  });

  testWidgets('returns confirmation only after the explicit sign-in action', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showExistingAccountSwitchDialog(context);
            },
            child: const Text('Upgrade'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    check(result).equals(true);
  });
}
