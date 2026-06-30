import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_engine/features/profile/data/models/user_profile.dart';

/// Repository for user profile data operations.
///
/// Handles CRUD operations for user data, combining `users` and `user_profiles`
/// tables in a single query. Auth-agnostic - userId must be provided by caller.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  /// Fetches a user's complete profile (users + user_profiles joined).
  Future<UserProfile> getUserProfile(String userId) async {
    // Query user_profiles and join with users table
    final response = await _client
        .from('user_profiles')
        .select('''
          id,
          display_name,
          avatar_url,
          created_at,
          updated_at,
          users!inner (
            username,
            email,
            payment_tier
          )
        ''')
        .eq('id', userId)
        .single();

    // Flatten the nested response
    final users = response['users'] as Map<String, dynamic>;
    return UserProfile.fromJson({
      'id': response['id'],
      'display_name': response['display_name'],
      'avatar_url': response['avatar_url'],
      'created_at': response['created_at'],
      'updated_at': response['updated_at'],
      'username': users['username'],
      'email': users['email'],
      'payment_tier': users['payment_tier'],
    });
  }

  /// Updates a user's profile.
  ///
  /// Returns the updated [UserProfile] on success.
  Future<UserProfile> updateProfile(
    String userId, {
    String? displayName,
    String? avatarUrl,
  }) async {
    final updates = <String, dynamic>{};

    if (displayName != null) updates['display_name'] = displayName;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

    if (updates.isNotEmpty) {
      await _client.from('user_profiles').update(updates).eq('id', userId);
    }

    // Re-fetch the complete profile
    return getUserProfile(userId);
  }

  /// Updates the current user's username via RPC.
  ///
  /// Throws on validation or uniqueness errors.
  Future<String> updateUsername(String newUsername) async {
    final response = await _client.rpc(
      'app_update_username',
      params: {'new_username': newUsername},
    );
    return response as String;
  }
}
