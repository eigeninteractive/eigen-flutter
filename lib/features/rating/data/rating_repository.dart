import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_engine/features/rating/data/models/player_rating.dart';

/// Repository for player rating data.
///
/// Reads directly from [player_ratings] via RLS-protected table queries.
/// Writes are performed exclusively by the `update-ratings` Edge Function.
/// Rating history is fetched as part of [GameRepository.getHistoryGameEntries].
class RatingRepository {
  RatingRepository(this._client);

  final SupabaseClient _client;

  /// Returns all pool ratings for [id], ordered by highest display rating.
  ///
  /// Works for both human and bot IDs — queries both [user_id] and [bot_id]
  /// columns since the XOR constraint guarantees exactly one is set per row.
  Future<List<PlayerRating>> getPlayerRatings(String id) async {
    final response = await _client
        .from('player_ratings')
        .select('pool, mu, sigma, display_rating')
        .or('user_id.eq.$id,bot_id.eq.$id')
        .order('display_rating', ascending: false);
    return response.map(PlayerRating.fromJson).toList();
  }
}
