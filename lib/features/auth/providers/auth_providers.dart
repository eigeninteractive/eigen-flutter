import 'dart:async';

import 'dart:developer' as developer;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_flutter/core/analytics/analytics_provider.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:eigen_flutter/core/notifications/notification_provider.dart';
import 'package:eigen_flutter/core/storage/storage_provider.dart';
import 'package:eigen_flutter/features/auth/data/auth_service.dart';
import 'package:eigen_flutter/features/auth/data/models/auth_user.dart';
import 'package:eigen_flutter/features/profile/providers/profile_providers.dart';
import 'package:eigen_flutter/shared/providers/player_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';

part 'auth_providers.g.dart';

/// Result of [AuthController.upgradeToGoogle], so the UI can tailor feedback.
enum UpgradeOutcome {
  /// The Google identity was linked to the existing guest account; all games,
  /// ratings, and friends are preserved.
  linked,

  /// The Google identity already belongs to an account. The UI must ask before
  /// abandoning guest progress and calling [AuthController.switchToExisting].
  existingAccount,
}

/// Provider for AuthService instance
@Riverpod(keepAlive: true)
AuthGateway authService(Ref ref) {
  final googleWebClientId = ref
      .watch(appConfigProvider)
      .engine
      .googleWebClientId;
  return AuthService(
    FirebaseAuth.instance,
    googleWebClientId: googleWebClientId,
  );
}

/// The signed-in user's id, or null when signed out.
///
/// Derived from the auth state stream. Because the value is a [String],
/// Riverpod's `==` check means dependents only rebuild when the id actually
/// changes; token refreshes re-emit the same id and propagate no further.
@riverpod
String? currentUserId(Ref ref) =>
    ref.watch(authStateChangesProvider).value?.user?.id;

/// Provider for current authenticated user.
///
/// Rebuilds when the signed-in user changes (sign-in, sign-out, account
/// switch) so user-scoped providers watching this re-key per account.
@riverpod
AuthUser? currentUser(Ref ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(authServiceProvider).currentUser;
}

/// Provider for authentication state stream
@riverpod
Stream<AuthStateChange> authStateChanges(Ref ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
}

/// Whether the current session is an anonymous (guest) session.
///
/// Watches the auth state stream (not [currentUserId]) so it re-evaluates on
/// `userUpdated` events: the id is unchanged when a guest upgrades, but the
/// `isAnonymous` claim flips to false. UI gates (social, rated games, upgrade
/// nudge) watch this; `==` on the bool keeps unrelated token refreshes inert.
@riverpod
bool isAnonymous(Ref ref) {
  final user = ref.watch(authStateChangesProvider).value?.user;
  return user?.isAnonymous ?? false;
}

/// Authentication controller for managing auth operations
/// Manages operation state (loading/error) for auth actions like sign-in/sign-out
@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  AuthCredential? _pendingExistingAccountCredential;
  bool _hasPendingExistingAccount = false;

  @override
  AsyncValue<void> build() {
    // No initial state - this controller only manages operation state
    return const AsyncData(null);
  }

  /// Sign in with Google
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithGoogle();
      // Don't return user - currentUserProvider handles that
    });
  }

  /// Start an anonymous (guest) session.
  Future<void> signInAnonymously() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      await ref.read(authServiceProvider).signInAnonymously();
    });
  }

  /// Upgrade the current guest session to a permanent Google account.
  ///
  /// On success the user id is preserved, so games/ratings/friends carry over;
  /// the DB trigger backfills email/name/avatar and we invalidate the cached
  /// identity so the new values surface immediately. If the Google account
  /// already exists, returns [UpgradeOutcome.existingAccount] without changing
  /// the session. The UI must obtain explicit confirmation and then call
  /// [switchToExisting].
  ///
  /// Returns which path ran so the caller can tailor its confirmation; throws
  /// on failure (e.g. the user cancels the Google sheet).
  Future<UpgradeOutcome> upgradeToGoogle() async {
    state = const AsyncLoading();

    final authService = ref.read(authServiceProvider);
    final analytics = ref.read(analyticsServiceProvider);
    final guestId = ref.read(currentUserProvider)?.id;
    try {
      try {
        await authService.upgradeWithGoogle();
        if (guestId != null) {
          ref.invalidate(currentUserProfileProvider);
          ref.invalidate(playerInfoCacheProvider(id: guestId));
        }
        unawaited(analytics.guestUpgraded());
        unawaited(analytics.setAccountType(isGuest: false));
        state = const AsyncData(null);
        return UpgradeOutcome.linked;
      } on AccountExistsException catch (error) {
        _pendingExistingAccountCredential = error.credential;
        _hasPendingExistingAccount = true;
        state = const AsyncData(null);
        return UpgradeOutcome.existingAccount;
      }
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// Abandons the guest session and signs into the existing Google account
  /// selected by the preceding [upgradeToGoogle] attempt.
  ///
  /// This is deliberately separate from conflict detection so the UI can
  /// explain that guest progress cannot be transferred and obtain consent
  /// before any local teardown or account switch occurs.
  Future<void> switchToExisting() async {
    if (!_hasPendingExistingAccount) {
      throw StateError('No existing Google account switch is pending.');
    }

    state = const AsyncLoading();
    final credential = _pendingExistingAccountCredential;
    final guestId = ref.read(currentUserProvider)?.id;
    try {
      await ref
          .read(authServiceProvider)
          .switchToExistingGoogleAccount(credential);
      // Keep the guest session and its local state intact until the account
      // switch really succeeds. The signed-in auth event re-registers this
      // installation for the destination account.
      if (guestId != null) {
        try {
          await deleteUserData(ref, guestId);
        } catch (error, stackTrace) {
          // The identity switch has already succeeded. These values are only
          // disposable guest cache entries, so a cleanup failure must not make
          // the UI report the sign-in itself as failed.
          developer.log(
            'Guest cache cleanup after account switch failed (ignored)',
            name: 'auth.providers',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    } finally {
      _pendingExistingAccountCredential = null;
      _hasPendingExistingAccount = false;
    }
  }

  /// Keeps the current guest session after the user declines an account switch.
  void cancelExistingAccountSwitch() {
    _pendingExistingAccountCredential = null;
    _hasPendingExistingAccount = false;
  }

  /// Permanently deletes the current user's account.
  ///
  /// Two steps, in this order and no other: the server tears the account down
  /// (forfeiting live games, deleting the identity, purging the database), and
  /// only then is the local session cleared. Signing out first would leave no
  /// token to authenticate the deletion with.
  ///
  /// The sign-out is best-effort: the identity is already gone by then, so the
  /// provider may refuse to invalidate a session that no longer exists, and
  /// reporting that as a failed deletion would be a lie.
  Future<void> deleteAccount() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final userId = ref.read(currentUserProvider)?.id;
      await ref.read(profileRepositoryProvider).deleteAccount();
      if (userId != null) await deleteUserData(ref, userId);
      try {
        await ref.read(authServiceProvider).signOut();
      } catch (error) {
        developer.log(
          'Sign-out after account deletion failed (ignored)',
          name: 'auth.providers',
          error: error,
        );
      }
    });
  }

  /// Sign out current user
  Future<void> signOut() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) await deleteUserData(ref, userId);
      // Remove this install's notification registration before clearing the
      // session so the server stops delivering notifications immediately. Errors
      // are caught inside deleteCurrentInstallation and never block sign-out.
      await ref.read(notificationServiceProvider).deleteCurrentInstallation();
      await ref.read(authServiceProvider).signOut();
    });
  }
}
