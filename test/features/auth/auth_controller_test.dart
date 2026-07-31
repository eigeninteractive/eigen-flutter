import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/analytics/analytics_provider.dart';
import 'package:eigen_flutter/core/analytics/analytics_service.dart';
import 'package:eigen_flutter/core/storage/storage_provider.dart';
import 'package:eigen_flutter/features/auth/data/auth_service.dart';
import 'package:eigen_flutter/features/auth/data/models/auth_user.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/container.dart';

final class _FakeAuthGateway implements AuthGateway {
  bool throwExistingAccount = false;
  bool switched = false;

  @override
  AuthUser? get currentUser => const AuthUser(id: 'guest-1', isAnonymous: true);

  @override
  Stream<AuthStateChange> get authStateChanges => const Stream.empty();

  @override
  Future<void> signInAnonymously() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> switchToExistingGoogleAccount(AuthCredential? credential) async {
    switched = true;
  }

  @override
  Future<void> upgradeWithGoogle() async {
    if (throwExistingAccount) throw const AccountExistsException(null);
  }
}

final class _FakeAnalytics implements AnalyticsService {
  @override
  Future<void> friendAccepted() async {}

  @override
  Future<void> friendRequestSent() async {}

  @override
  Future<void> forfeit() async {}

  @override
  Future<void> gameCreated({
    required String gameId,
    required String access,
    required String timingMode,
    required bool rated,
  }) async {}

  @override
  Future<void> gameFinished({required String gameId}) async {}

  @override
  Future<void> gameStarted({
    required String gameId,
    required int playerCount,
  }) async {}

  @override
  Future<void> guestUpgraded() async {}

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> joinByCode() async {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> setAccountType({required bool isGuest}) async {}

  @override
  Future<void> wireEnumFallback({
    required String enumType,
    required String surface,
  }) async {}
}

void main() {
  test(
    'an existing Google account requires confirmation before switching',
    () async {
      final auth = _FakeAuthGateway()..throwExistingAccount = true;
      final container = makeContainer(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          analyticsServiceProvider.overrideWithValue(_FakeAnalytics()),
          currentUserProvider.overrideWith(
            (ref) => const AuthUser(id: 'guest-1', isAnonymous: true),
          ),
        ],
      );

      final controller = container.read(authControllerProvider.notifier);
      final outcome = await controller.upgradeToGoogle();

      check(outcome).equals(UpgradeOutcome.existingAccount);
      check(auth.switched).isFalse();
      expect(container.read(authControllerProvider), isA<AsyncData<void>>());

      controller.cancelExistingAccountSwitch();
      await check(controller.switchToExisting()).throws<StateError>();
      check(auth.switched).isFalse();
    },
  );

  test('a new Google account links without asking to switch', () async {
    final auth = _FakeAuthGateway();
    final container = makeContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        analyticsServiceProvider.overrideWithValue(_FakeAnalytics()),
        currentUserProvider.overrideWith(
          (ref) => const AuthUser(id: 'guest-1', isAnonymous: true),
        ),
      ],
    );

    final outcome = await container
        .read(authControllerProvider.notifier)
        .upgradeToGoogle();

    check(outcome).equals(UpgradeOutcome.linked);
    check(auth.switched).isFalse();
  });

  test('switches to the existing account only after confirmation', () async {
    final auth = _FakeAuthGateway()..throwExistingAccount = true;
    final container = makeContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        analyticsServiceProvider.overrideWithValue(_FakeAnalytics()),
        currentUserProvider.overrideWith(
          (ref) => const AuthUser(id: 'guest-1', isAnonymous: true),
        ),
        storageProvider.overrideWith((ref) async => Storage.inMemory()),
      ],
    );

    final controller = container.read(authControllerProvider.notifier);
    await controller.upgradeToGoogle();
    await controller.switchToExisting();

    check(auth.switched).isTrue();
    expect(container.read(authControllerProvider), isA<AsyncData<void>>());
  });
}
