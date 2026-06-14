import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_engine/core/config/app_config.dart';
import 'package:eigen_engine/core/notifications/notification_provider.dart';
import 'package:eigen_engine/core/storage/storage_provider.dart';
import 'package:eigen_engine/features/auth/data/auth_service.dart';

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
