import 'dart:async';
import 'dart:developer' as developer;

import 'package:eigen_flutter/features/auth/data/models/auth_user.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The authentication boundary.
///
/// Firebase types stay private to this file; the public surface speaks only the
/// domain types in `auth_user.dart`. The engine never sees a password or a
/// provider credential - it only ever verifies the Firebase ID token that
/// results, which the transport layer attaches to every request.
class AuthService {
  AuthService(this._auth, {required this.googleWebClientId});

  final FirebaseAuth _auth;

  /// Google Sign-In server client id, injected from `EngineConfig`.
  final String googleWebClientId;

  /// The current authenticated user, or null when signed out.
  AuthUser? get currentUser => _toAuthUser(_auth.currentUser);

  /// Authentication state over time.
  ///
  /// Built on `userChanges()` rather than `authStateChanges()` deliberately: a
  /// guest upgrade keeps the same uid and only flips `isAnonymous`, which
  /// `authStateChanges()` does not report. Downstream state that depends on
  /// guest-ness would silently go stale.
  ///
  /// Firebase has no event taxonomy - it emits a user or null - so the event is
  /// derived by diffing consecutive emissions. That is also what makes an
  /// account switch (guest abandoned for an existing Google account) report as
  /// a fresh sign-in rather than an update, since the uid changes.
  Stream<AuthStateChange> get authStateChanges {
    AuthUser? previous;
    var seenFirst = false;
    return _auth.userChanges().map((user) {
      final next = _toAuthUser(user);
      final event = _eventFor(previous, next, isFirst: !seenFirst);
      previous = next;
      seenFirst = true;
      return AuthStateChange(event: event, user: next);
    });
  }

  AuthEvent _eventFor(
    AuthUser? previous,
    AuthUser? next, {
    required bool isFirst,
  }) {
    if (next == null) return AuthEvent.signedOut;
    // A restored session on launch is a sign-in as far as consumers care: it
    // is where analytics identity and push registration are established.
    if (isFirst || previous == null || previous.id != next.id) {
      return AuthEvent.signedIn;
    }
    return AuthEvent.userUpdated;
  }

  AuthUser? _toAuthUser(User? user) =>
      user == null ? null : AuthUser(id: user.uid, isAnonymous: user.isAnonymous);

  /// Runs the native Google Sign-In flow and builds a Firebase credential.
  ///
  /// Shared by sign-in and guest upgrade so both use the same native account
  /// picker rather than a browser redirect.
  Future<OAuthCredential> _googleCredential() async {
    final signIn = GoogleSignIn.instance;
    await signIn.initialize(serverClientId: googleWebClientId);

    final account = await signIn.authenticate();
    final authorization = await account.authorizationClient
        .authorizationForScopes(['email', 'profile']);
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception('Google sign-in returned no ID token.');
    }
    return GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: authorization?.accessToken,
    );
  }

  /// Signs in with Google, creating the account on first use.
  Future<void> signInWithGoogle() async {
    try {
      await _auth.signInWithCredential(await _googleCredential());
      developer.log('Signed in with Google', name: 'auth.service');
    } catch (error, stackTrace) {
      developer.log(
        'Failed to sign in with Google',
        name: 'auth.service',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Starts a guest session so a visitor can play without signing up.
  ///
  /// The engine provisions a real user for the anonymous uid on first request,
  /// generated handle and all; [upgradeWithGoogle] converts it later without
  /// losing anything.
  Future<void> signInAnonymously() async {
    try {
      await _auth.signInAnonymously();
      developer.log('Guest session started', name: 'auth.service');
    } catch (error, stackTrace) {
      developer.log(
        'Failed to start guest session',
        name: 'auth.service',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Converts the current guest into a permanent Google account.
  ///
  /// Links the Google identity to the existing uid, so games, ratings and
  /// friends carry over untouched - the engine keys everything on that uid and
  /// never learns the account changed.
  ///
  /// Throws [AccountExistsException] when the chosen Google account already
  /// belongs to someone: the two identities cannot merge, so the caller offers
  /// to switch into that account instead and abandon the guest data.
  Future<void> upgradeWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No guest session to upgrade.');
    }
    try {
      await user.linkWithCredential(await _googleCredential());
      developer.log('Guest upgraded to Google', name: 'auth.service');
    } on FirebaseAuthException catch (error, stackTrace) {
      // Both codes mean the same thing to a user: that Google account is taken.
      if (error.code == 'credential-already-in-use' ||
          error.code == 'email-already-in-use') {
        throw const AccountExistsException();
      }
      developer.log(
        'Failed to upgrade guest account',
        name: 'auth.service',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Signs into an existing Google account, abandoning the current guest.
  Future<void> switchToExistingGoogleAccount() => signInWithGoogle();

  /// Clears the local session.
  ///
  /// After an account deletion the server has already removed the identity, so
  /// this may fail; callers deleting an account swallow that rather than
  /// reporting a successful deletion as a failure.
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      developer.log('Signed out', name: 'auth.service');
    } catch (error, stackTrace) {
      developer.log(
        'Failed to sign out',
        name: 'auth.service',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}

/// Thrown by [AuthService.upgradeWithGoogle] when the selected Google account
/// already belongs to a registered user, so the guest cannot be linked to it.
class AccountExistsException implements Exception {
  const AccountExistsException();

  @override
  String toString() => 'AccountExistsException: Google account already in use';
}
