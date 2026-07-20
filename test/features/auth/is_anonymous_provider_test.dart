import 'package:checks/checks.dart';
import 'package:eigen_flutter/features/auth/data/models/auth_user.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/container.dart';

AuthStateChange _signedIn({required bool isAnonymous}) => AuthStateChange(
  event: AuthEvent.signedIn,
  user: AuthUser(id: 'user-1', isAnonymous: isAnonymous),
);

/// Reads [isAnonymousProvider] after the overridden auth stream has emitted
/// [state]. Keeps a live subscription so the auto-dispose stream provider isn't
/// collected before its first value arrives.
Future<bool> _isAnonymous(AuthStateChange state) async {
  final container = makeContainer(
    overrides: [
      authStateChangesProvider.overrideWith((ref) => Stream.value(state)),
    ],
  );
  final sub = container.listen(isAnonymousProvider, (_, _) {});
  addTearDown(sub.close);

  await container.read(authStateChangesProvider.future);
  return container.read(isAnonymousProvider);
}

void main() {
  group('isAnonymousProvider', () {
    test('is true for an anonymous (guest) session', () async {
      check(await _isAnonymous(_signedIn(isAnonymous: true))).isTrue();
    });

    test('is false for a permanent session', () async {
      check(await _isAnonymous(_signedIn(isAnonymous: false))).isFalse();
    });

    test('is false when signed out (no session)', () async {
      check(
        await _isAnonymous(
          const AuthStateChange(event: AuthEvent.signedOut, user: null),
        ),
      ).isFalse();
    });
  });
}
