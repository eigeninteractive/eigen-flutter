import 'package:eigen_engine/shared/data/models/player_info.dart';
import 'package:eigen_engine/features/social/data/models/friendship.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SocialRepository {
  SocialRepository(this._client);

  final SupabaseClient _client;

  /// Invoke a `social` edge-function route. The friend *writes* go through the EF
  /// (gated `engine_*` RPCs) so it can emit the friend-request / accepted FCM
  /// pushes directly. Unwraps `{ "error": "<message>" }` like the game wrapper.
  Future<void> _invokeSocial(String route, Map<String, dynamic> body) async {
    try {
      await _client.functions.invoke('social/$route', body: body);
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'Edge function error (status ${e.status})';
      throw Exception(message);
    }
  }

  Future<List<Friendship>> getFriendships() async {
    final response = await _client.from('friends_view').select();
    return response.map((json) => Friendship.fromJson(json)).toList();
  }

  /// Latency-sensitive autocomplete read — stays a direct RPC (no notification),
  /// not routed through the social edge function.
  Future<List<PlayerInfo>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final response = await _client.rpc(
      'app_search_users',
      params: {'p_query': query},
    );
    return (response as List).map((json) => PlayerInfo.fromJson(json)).toList();
  }

  Future<void> sendFriendRequest(String targetUserId) =>
      _invokeSocial('friend-request', {'target_user_id': targetUserId});

  Future<void> acceptFriendRequest(String targetUserId) =>
      _invokeSocial('accept', {'target_user_id': targetUserId});

  Future<void> removeFriend(String targetUserId) =>
      _invokeSocial('remove', {'target_user_id': targetUserId});
}
