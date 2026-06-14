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

  /// Sign in with Google
  Future<AuthResponse> signInWithGoogle() async {
    try {
      final GoogleSignIn signIn = GoogleSignIn.instance;
      await signIn.initialize(serverClientId: googleWebClientId);

      final googleAccount = await signIn.authenticate();
      final googleAuthorization = await googleAccount.authorizationClient
          .authorizationForScopes(['email', 'profile']);
      final googleAuthentication = googleAccount.authentication;
      final idToken = googleAuthentication.idToken;
      final accessToken = googleAuthorization?.accessToken;

      if (idToken == null) {
        throw Exception('No ID Token found.');
      }

      final authResponse = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
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

  /// Permanently deletes the current user's account.
  ///
  /// Removes the avatar from storage (best-effort), then calls the
  /// `delete_account` RPC which deletes the auth row and cascades to all
  /// application data. Signs out locally so the auth state stream transitions
  /// to signed-out and the router navigates to the login screen.
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

      await _supabase.rpc('delete_account');

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
