import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_user.freezed.dart';

/// The signed-in user as the app sees it — the backend-agnostic twin of the
/// auth provider's session user.
///
/// Carries only the fields the app actually consumes. Identity details
/// (email, display name, avatar) live in the profile, not here.
@freezed
abstract class AuthUser with _$AuthUser {
  const factory AuthUser({required String id, required bool isAnonymous}) =
      _AuthUser;
}

/// Auth lifecycle events surfaced by [AuthService.authStateChanges].
///
/// [userUpdated] matters beyond the obvious three: a guest upgrade keeps the
/// user id but flips [AuthUser.isAnonymous], and it arrives as a userUpdated
/// event — `isAnonymousProvider` depends on it propagating.
enum AuthEvent {
  initialSession,
  signedIn,
  signedOut,
  tokenRefreshed,
  userUpdated,

  /// Any provider-specific event the app has no behavior for.
  other,
}

/// A single emission of the auth state stream: what happened, and who the
/// session user is now (null when signed out).
@freezed
abstract class AuthStateChange with _$AuthStateChange {
  const factory AuthStateChange({
    required AuthEvent event,
    required AuthUser? user,
  }) = _AuthStateChange;
}
