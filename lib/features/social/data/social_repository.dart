import 'package:eigen_engine/shared/data/models/player_info.dart';
import 'package:eigen_engine/features/social/data/models/friendship.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SocialRepository {
  SocialRepository(this._client);

  final SupabaseClient _client;

  Future<List<Friendship>> getFriendships() async {
    final response = await _client.from('friends_view').select();
    return response.map((json) => Friendship.fromJson(json)).toList();
  }

  Future<List<PlayerInfo>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final response = await _client.rpc(
      'search_users',
      params: {'p_query': query},
    );
    return (response as List).map((json) => PlayerInfo.fromJson(json)).toList();
  }

  Future<void> sendFriendRequest(String targetUserId) async {
    await _client.rpc(
      'send_friend_request',
      params: {'p_target_user_id': targetUserId},
    );
  }

  Future<void> acceptFriendRequest(String targetUserId) async {
    await _client.rpc(
      'accept_friend_request',
      params: {'p_target_user_id': targetUserId},
    );
  }

  Future<void> removeFriend(String targetUserId) async {
    await _client.rpc(
      'remove_friend',
      params: {'p_target_user_id': targetUserId},
    );
  }
}
