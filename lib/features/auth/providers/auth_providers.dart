import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_engine/core/config/app_config.dart';
import 'package:eigen_engine/core/notifications/notification_provider.dart';
import 'package:eigen_engine/core/storage/storage_provider.dart';
import 'package:eigen_engine/features/auth/data/auth_service.dart';
import 'package:eigen_engine/features/profile/providers/profile_providers.dart';
import 'package:eigen_engine/shared/providers/player_providers.dart';

part 'auth_providers.g.dart';

/// Provider for Supabase client instance
@Riverpod(keepAlive: true)
SupabaseClient supabaseClient(Ref ref) {
  return Supabase.instance.client;
}

/// Provider for AuthService instance
@Riverpod(keepAlive: true)
AuthService authService(Ref ref) {
  final supabase = ref.watch(supabaseClientProvider);
  final googleWebClientId = ref
      .watch(appConfigProvider)
      .engine
      .googleWebClientId;
  return AuthService(supabase, googleWebClientId: googleWebClientId);
}

/// The signed-in user's id, or null when signed out.
///
/// Derived from the auth state stream. Because the value is a [String],
/// Riverpod's `==` check means dependents only rebuild when the id actually
/// changes — token refreshes re-emit the same id and propagate no further.
@riverpod
String? currentUserId(Ref ref) =>
    ref.watch(authStateChangesProvider).value?.session?.user.id;

/// Provider for current authenticated user.
///
/// Rebuilds when the signed-in user changes (sign-in, sign-out, account
/// switch) so user-scoped providers watching this re-key per account.
@riverpod
User? currentUser(Ref ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(authServiceProvider).currentUser;
}

/// Provider for authentication state stream
@riverpod
Stream<AuthState> authStateChanges(Ref ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
}

/// Whether the current session is an anonymous (guest) session.
///
/// Watches the auth state stream (not [currentUserId]) so it re-evaluates on
/// `userUpdated` events — the id is unchanged when a guest upgrades, but the
/// `is_anonymous` claim flips to false. UI gates (social, rated games, upgrade
/// nudge) watch this; `==` on the bool keeps unrelated token refreshes inert.
@riverpod
bool isAnonymous(Ref ref) {
  final user = ref.watch(authStateChangesProvider).value?.session?.user;
  return user?.isAnonymous ?? false;
}

/// Authentication controller for managing auth operations
/// Manages operation state (loading/error) for auth actions like sign-in/sign-out
@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
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
  /// already exists, we switch into it instead — clearing the abandoned guest's
  /// local data and FCM token first, matching [signOut]'s teardown.
  Future<void> upgradeToGoogle() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final authService = ref.read(authServiceProvider);
      final guestId = ref.read(currentUserProvider)?.id;
      try {
        await authService.upgradeWithGoogle();
        if (guestId != null) {
          ref.invalidate(currentUserProfileProvider);
          ref.invalidate(playerInfoCacheProvider(id: guestId));
        }
      } on AccountExistsException {
        // Abandon the guest session and switch into the existing account.
        if (guestId != null) await deleteUserData(ref, guestId);
        await ref.read(notificationServiceProvider).deleteCurrentToken();
        await authService.switchToExistingGoogleAccount();
      }
    });
  }

  /// Permanently deletes the current user's account.
  Future<void> deleteAccount() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) await deleteUserData(ref, userId);
      await ref.read(authServiceProvider).deleteAccount();
    });
  }

  /// Sign out current user
  Future<void> signOut() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) await deleteUserData(ref, userId);
      // Delete the FCM token before clearing the session so the server stops
      // delivering notifications to this install immediately. Errors are caught
      // inside deleteCurrentToken and never block sign-out.
      await ref.read(notificationServiceProvider).deleteCurrentToken();
      await ref.read(authServiceProvider).signOut();
    });
  }
}
