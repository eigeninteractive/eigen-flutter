import 'dart:async';
import 'dart:developer' as developer;

import 'package:eigen_flutter/features/auth/data/models/auth_user.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The authentication boundary.
///
/// The app-facing identity and event surface uses the domain types in
/// `auth_user.dart`; the credential is carried only between the Firebase-backed
/// upgrade steps. The engine never sees a password or provider credential - it
/// only verifies the Firebase ID token that results, which the transport layer
/// attaches to every request.
abstract interface class AuthGateway {
  AuthUser? get currentUser;
  Stream<AuthStateChange> get authStateChanges;
  Future<void> signInWithGoogle();
  Future<void> signInAnonymously();
  Future<void> upgradeWithGoogle();
  Future<void> switchToExistingGoogleAccount(AuthCredential? credential);
  Future<void> signOut();
}

/// Firebase-backed implementation of [AuthGateway].
class AuthService implements AuthGateway {
  AuthService(this._auth, {required this.googleWebClientId});

  final FirebaseAuth _auth;

  /// Google Sign-In server client id, injected from `EngineConfig`.
  final String googleWebClientId;

  /// The current authenticated user, or null when signed out.
  @override
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
  @override
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

  AuthUser? _toAuthUser(User? user) => user == null
      ? null
      : AuthUser(id: user.uid, isAnonymous: user.isAnonymous);

  /// Runs the native Google authentication flow and builds a Firebase
  /// credential.
  ///
  /// Authentication needs only Google's ID token. Requesting a Google API
  /// access token here would conflate sign-in with authorization for unrelated
  /// Google services and can introduce an unnecessary consent prompt.
  Future<OAuthCredential> _googleCredential() async {
    final signIn = GoogleSignIn.instance;
    await signIn.initialize(serverClientId: googleWebClientId);

    final account = await signIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception('Google sign-in returned no ID token.');
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  GoogleAuthProvider _googleProvider() => GoogleAuthProvider();

  /// Signs in with Google, creating the account on first use.
  @override
  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // google_sign_in's endorsed web implementation deliberately does not
        // support authenticate(): Google Identity Services requires its own
        // rendered button. Firebase Auth owns this app's session already, so
        // its popup flow is the simpler supported browser integration.
        await _auth.signInWithPopup(_googleProvider());
      } else {
        await _auth.signInWithCredential(await _googleCredential());
      }
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
  @override
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
  @override
  Future<void> upgradeWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No guest session to upgrade.');
    }
    try {
      if (kIsWeb) {
        await user.linkWithPopup(_googleProvider());
      } else {
        await user.linkWithCredential(await _googleCredential());
      }
      developer.log('Guest upgraded to Google', name: 'auth.service');
    } on FirebaseAuthException catch (error, stackTrace) {
      // Both codes mean the same thing to a user: that Google account is taken.
      if (error.code == 'credential-already-in-use' ||
          error.code == 'email-already-in-use') {
        throw AccountExistsException(error.credential);
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
  ///
  /// Reuses the credential returned by a failed link when Firebase provides
  /// one, avoiding a second account prompt. Some providers/platforms omit it,
  /// in which case the normal sign-in flow is the safe fallback.
  @override
  Future<void> switchToExistingGoogleAccount(AuthCredential? credential) =>
      credential == null
      ? signInWithGoogle()
      : _auth.signInWithCredential(credential);

  /// Clears the local session.
  ///
  /// After an account deletion the server has already removed the identity, so
  /// this may fail; callers deleting an account swallow that rather than
  /// reporting a successful deletion as a failure.
  @override
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
  const AccountExistsException(this.credential);

  /// Credential recovered from the failed link, when the platform exposes it.
  final AuthCredential? credential;

  @override
  String toString() => 'AccountExistsException: Google account already in use';
}
