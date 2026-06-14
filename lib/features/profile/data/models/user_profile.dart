import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_profile.freezed.dart';
part 'user_profile.g.dart';

/// Combined user profile containing both system data and editable fields.
///
/// Merges data from `users` table (system-managed: username, email, etc.)
/// and `user_profiles` table (user-editable: displayName, avatarUrl).
@freezed
abstract class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String id,

    // From users table (system-managed)
    required String username,
    required String email,
    required String paymentTier,

    // From user_profiles table (user-editable)
    required String displayName,
    String? avatarUrl,

    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
}
