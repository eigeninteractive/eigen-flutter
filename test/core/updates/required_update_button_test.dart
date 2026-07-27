import 'package:eigen_flutter/core/updates/app_update_gateway.dart';
import 'package:eigen_flutter/core/updates/required_update_button.dart';
import 'package:eigen_flutter/core/updates/update_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('web action is labelled Reload App and reloads the browser', (
    tester,
  ) async {
    final gateway = _WidgetUpdateGateway(ClientUpdatePlatform.web);
    await tester.pumpWidget(_app(gateway));

    expect(find.text('Reload App'), findsOneWidget);

    await tester.tap(find.text('Reload App'));
    await tester.pump();

    expect(gateway.reloads, 1);
  });

  testWidgets('Android action is labelled Update App', (tester) async {
    final gateway = _WidgetUpdateGateway(ClientUpdatePlatform.androidPlay);
    await tester.pumpWidget(_app(gateway));

    expect(find.text('Update App'), findsOneWidget);
  });

  testWidgets('unsupported platforms do not show a false update action', (
    tester,
  ) async {
    final gateway = _WidgetUpdateGateway(ClientUpdatePlatform.unsupported);
    await tester.pumpWidget(_app(gateway));

    expect(find.byType(RequiredUpdateButton), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}

Widget _app(AppUpdateGateway gateway) => ProviderScope(
  overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
  child: const MaterialApp(home: Scaffold(body: RequiredUpdateButton())),
);

final class _WidgetUpdateGateway implements AppUpdateGateway {
  _WidgetUpdateGateway(this.platform);

  @override
  final ClientUpdatePlatform platform;

  int reloads = 0;

  @override
  Future<void> reloadWeb() async {
    reloads++;
  }

  @override
  Future<NativeUpdateAvailability> checkForUpdate() async =>
      NativeUpdateAvailability.none;

  @override
  Future<void> completeFlexibleUpdate() async {}

  @override
  Future<NativeUpdateAttempt> performImmediateUpdate() async =>
      NativeUpdateAttempt.success;

  @override
  Future<NativeUpdateAttempt> startFlexibleUpdate() async =>
      NativeUpdateAttempt.success;
}
