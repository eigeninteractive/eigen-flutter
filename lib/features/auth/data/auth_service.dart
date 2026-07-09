import 'dart:async';
import 'dart:developer' as developer;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Authentication service that handles Google Sign-In with Supabase
class AuthService {
  AuthService(this._supabase, {required this.googleWebClientId});

  final SupabaseClient _supabase;

  /// Google Sign-In server client id, injected from [EngineConfig].
  final String googleWebClientId;

  /// Get the current authenticated user
  User? get currentUser => _supabase.auth.currentUser;

  /// Stream of authentication state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Runs the native Google Sign-In flow and returns the resulting tokens.
  ///
  /// Shared by [signInWithGoogle] and [upgradeWithGoogle] so both use the same
  /// native account picker rather than a browser redirect.
  Future<({String idToken, String? accessToken})> _googleTokens() async {
    final GoogleSignIn signIn = GoogleSignIn.instance;
    await signIn.initialize(serverClientId: googleWebClientId);

    final googleAccount = await signIn.authenticate();
    final googleAuthorization = await googleAccount.authorizationClient
        .authorizationForScopes(['email', 'profile']);
    final idToken = googleAccount.authentication.idToken;

    if (idToken == null) {
      throw Exception('No ID Token found.');
    }
    return (idToken: idToken, accessToken: googleAuthorization?.accessToken);
  }

  /// Sign in with Google
  Future<AuthResponse> signInWithGoogle() async {
    try {
      final tokens = await _googleTokens();

      final authResponse = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );

      developer.log(
        'User signed in: ${authResponse.user?.email}',
        name: 'auth.service',
      );

      return authResponse;
    } catch (e, stackTrace) {
      developer.log(
        'Failed to sign in with Google',
        name: 'auth.service',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Starts an anonymous (guest) session so a visitor can try the app without
  /// signing up. Provisions a real `authenticated` user with a generated
  /// `player_NNNNN` handle; convert later via [upgradeWithGoogle].
  Future<AuthResponse> signInAnonymously() async {
    try {
      final authResponse = await _supabase.auth.signInAnonymously();
      developer.log('Anonymous (guest) session started', name: 'auth.service');
      return authResponse;
    } catch (e, stackTrace) {
      developer.log(
        'Failed to start anonymous session',
        name: 'auth.service',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Upgrades the current guest session to a permanent Google account, linking
  /// the Google identity to the existing user id so all their games, ratings,
  /// and friends carry over. The `on_auth_user_converted` DB trigger backfills
  /// the email, display name, and avatar.
  ///
  /// Throws [AccountExistsException] when the chosen Google account already
  /// belongs to a registered user — the caller switches into that account
  /// instead (guest data is abandoned).
  Future<void> upgradeWithGoogle() async {
    try {
      final tokens = await _googleTokens();
      await _supabase.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.google,
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
      developer.log('Guest upgraded to Google', name: 'auth.service');
    } on AuthException catch (e, stackTrace) {
      if (e.code == 'identity_already_exists') {
        throw const AccountExistsException();
      }
      developer.log(
        'Failed to upgrade guest account',
        name: 'auth.service',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Permanently deletes the current user's account.
  ///
  /// Removes the avatar from storage (best-effort), then invokes the
  /// `game/delete-account` edge-function route, which forfeits the caller's
  /// active games before deleting the auth row and cascading to all application
  /// data. Signs out locally so the auth state stream transitions to signed-out
  /// and the router navigates to the login screen.
  Future<void> deleteAccount() async {
    try {
      final userId = currentUser?.id;
      if (userId != null) {
        try {
          await _supabase.storage.from('avatars').remove([userId]);
        } catch (e) {
          developer.log(
            'Avatar removal skipped during account deletion',
            name: 'auth.service',
            error: e,
          );
        }
      }

      // Account teardown lives in the engine edge function: it forfeits the
      // caller's active games via the TS rules, then purges (cancel/leave +
      // delete the auth user).
      await _supabase.functions.invoke('engine/game/delete-account');

      // Clear the local session. The auth row is already gone so the server-
      // side invalidation call may fail — swallow any error here so a network
      // blip doesn't surface as "account deletion failed" to the user.
      try {
        await _supabase.auth.signOut();
      } catch (e) {
        developer.log(
          'Sign-out after account deletion failed (ignored)',
          name: 'auth.service',
          error: e,
        );
      }

      developer.log('Account deleted', name: 'auth.service');
    } catch (e, stackTrace) {
      developer.log(
        'Failed to delete account',
        name: 'auth.service',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Signs the user into a Google account that already exists in the app,
  /// switching away from (and abandoning) the current guest session.
  Future<AuthResponse> switchToExistingGoogleAccount() => signInWithGoogle();

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      developer.log('User signed out', name: 'auth.service');
    } catch (e, stackTrace) {
      developer.log(
        'Failed to sign out',
        name: 'auth.service',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}

/// Thrown by [AuthService.upgradeWithGoogle] when the selected Google account is
/// already registered, so the guest identity cannot be linked to it.
class AccountExistsException implements Exception {
  const AccountExistsException();

  @override
  String toString() => 'AccountExistsException: Google account already in use';
}
