import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_user.freezed.dart';

/// The signed-in user as the app sees it: the backend-agnostic twin of the
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
/// Derived by diffing consecutive sessions rather than reported by the provider,
/// so these are exactly the transitions the app acts on, with no provider-specific
/// events it has no behaviour for.
enum AuthEvent {
  /// A session began, was restored on launch, or switched to another account.
  /// The uid is new, so identity-scoped setup (analytics, push registration)
  /// belongs here.
  signedIn,

  /// The session ended.
  signedOut,

  /// Same user, changed session: a token refresh, or the guest upgrade that
  /// keeps the uid and flips [AuthUser.isAnonymous]. State that depends on
  /// guest-ness must re-read on this.
  userUpdated,
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
