import 'package:checks/checks.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/container.dart';

User _user({required bool isAnonymous}) => User(
  id: 'user-1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.utc(2026).toIso8601String(),
  isAnonymous: isAnonymous,
);

AuthState _signedIn({required bool isAnonymous}) => AuthState(
  AuthChangeEvent.signedIn,
  Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: _user(isAnonymous: isAnonymous),
  ),
);

/// Reads [isAnonymousProvider] after the overridden auth stream has emitted
/// [state]. Keeps a live subscription so the auto-dispose stream provider isn't
/// collected before its first value arrives.
Future<bool> _isAnonymous(AuthState state) async {
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
        await _isAnonymous(const AuthState(AuthChangeEvent.signedOut, null)),
      ).isFalse();
    });
  });
}
