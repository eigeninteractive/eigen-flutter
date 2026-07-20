import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_flutter/shared/data/db_guard.dart';
import 'package:eigen_flutter/shared/data/models/player_info.dart';

/// Thrown when a player lookup matches no row.
///
/// Deleted accounts leave no `app_players` row behind, so reaching this
/// usually means a synthetic deleted-seat placeholder id (see
/// `GamePlayer.isDeleted`) leaked into an identity lookup.
class PlayerNotFoundException implements Exception {
  const PlayerNotFoundException(this.playerId);

  /// The id that matched no player.
  final String playerId;

  @override
  String toString() => 'No player found for id: $playerId';
}

/// Repository for fetching public player identities.
///
/// Uses the `app_players` RPC, which covers both human users and bots via a
/// UNION. All data is public-safe (no email, no payment tier).
class PlayerRepository {
  PlayerRepository(this._client);

  final SupabaseClient _client;

  /// Fetches public identity for any player (human or bot) by ID.
  ///
  /// Throws [PlayerNotFoundException] when no player has this id.
  Future<PlayerInfo> getPlayer(String id) async {
    final response = await dbGuard(
      () => _client.rpc(
        'app_players',
        params: {
          'p_ids': [id],
        },
      ),
    );
    final rows = response as List;
    if (rows.isEmpty) throw PlayerNotFoundException(id);
    return PlayerInfo.fromJson(rows.single);
  }
}
