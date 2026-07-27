import 'package:eigen_flutter/core/updates/app_update_gateway.dart';
import 'package:eigen_flutter/core/updates/update_notifier.dart';
import 'package:eigen_flutter/core/navigation/providers/navigation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/container.dart';

void main() {
  test(
    'required update bypasses active-route guard for immediate Play update',
    () async {
      final gateway = _FakeUpdateGateway(
        availability: NativeUpdateAvailability.immediate,
      );
      final container = makeContainer(
        overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
      );

      final result = await container
          .read(updateProvider.notifier)
          .requestRequiredUpdate();

      expect(result, RequiredUpdateResult.started);
      expect(gateway.immediateAttempts, 1);
    },
  );

  test('required flexible Play update downloads and completes', () async {
    final gateway = _FakeUpdateGateway(
      availability: NativeUpdateAvailability.flexible,
    );
    final container = makeContainer(
      overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
    );

    final result = await container
        .read(updateProvider.notifier)
        .requestRequiredUpdate();

    expect(result, RequiredUpdateResult.started);
    expect(gateway.flexibleAttempts, 1);
    expect(gateway.completions, 1);
  });

  test('Android reports unavailable when Play has no update', () async {
    final gateway = _FakeUpdateGateway();
    final container = makeContainer(
      overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
    );

    final result = await container
        .read(updateProvider.notifier)
        .requestRequiredUpdate();

    expect(result, RequiredUpdateResult.unavailable);
    expect(gateway.reloads, 0);
  });

  testWidgets('background Play check does not interrupt an active game', (
    tester,
  ) async {
    final gateway = _FakeUpdateGateway(
      availability: NativeUpdateAvailability.immediate,
    );
    final router = GoRouter(
      initialLocation: '/game/active',
      routes: [
        GoRoute(path: '/game/:id', builder: (_, _) => const SizedBox.shrink()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    final container = makeContainer(
      overrides: [
        appUpdateGatewayProvider.overrideWithValue(gateway),
        goRouterProvider.overrideWithValue(router),
      ],
    );

    await container.read(updateProvider.notifier).checkForUpdate();

    expect(gateway.updateChecks, 1);
    expect(gateway.immediateAttempts, 0);
  });

  test('web reloads the current application without checking Play', () async {
    final gateway = _FakeUpdateGateway(platform: ClientUpdatePlatform.web);
    final container = makeContainer(
      overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
    );

    final result = await container
        .read(updateProvider.notifier)
        .requestRequiredUpdate();

    expect(result, RequiredUpdateResult.started);
    expect(gateway.reloads, 1);
    expect(gateway.updateChecks, 0);
  });

  test('web reload failure is reported', () async {
    final gateway = _FakeUpdateGateway(
      platform: ClientUpdatePlatform.web,
      reloadError: StateError('reload failed'),
    );
    final container = makeContainer(
      overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
    );

    final result = await container
        .read(updateProvider.notifier)
        .requestRequiredUpdate();

    expect(result, RequiredUpdateResult.failed);
  });

  test('unsupported platforms do not invent an update destination', () async {
    final gateway = _FakeUpdateGateway(
      platform: ClientUpdatePlatform.unsupported,
    );
    final container = makeContainer(
      overrides: [appUpdateGatewayProvider.overrideWithValue(gateway)],
    );

    final result = await container
        .read(updateProvider.notifier)
        .requestRequiredUpdate();

    expect(result, RequiredUpdateResult.unavailable);
    expect(gateway.updateChecks, 0);
    expect(gateway.reloads, 0);
  });
}

final class _FakeUpdateGateway implements AppUpdateGateway {
  _FakeUpdateGateway({
    this.availability = NativeUpdateAvailability.none,
    this.platform = ClientUpdatePlatform.androidPlay,
    this.reloadError,
  });

  NativeUpdateAvailability availability;

  @override
  final ClientUpdatePlatform platform;

  final Object? reloadError;
  int updateChecks = 0;
  int immediateAttempts = 0;
  int flexibleAttempts = 0;
  int completions = 0;
  int reloads = 0;

  @override
  Future<NativeUpdateAvailability> checkForUpdate() async {
    updateChecks++;
    return availability;
  }

  @override
  Future<NativeUpdateAttempt> performImmediateUpdate() async {
    immediateAttempts++;
    return NativeUpdateAttempt.success;
  }

  @override
  Future<NativeUpdateAttempt> startFlexibleUpdate() async {
    flexibleAttempts++;
    return NativeUpdateAttempt.success;
  }

  @override
  Future<void> completeFlexibleUpdate() async {
    completions++;
  }

  @override
  Future<void> reloadWeb() async {
    reloads++;
    if (reloadError case final error?) throw error;
  }
}
