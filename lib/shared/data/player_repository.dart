import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_engine/shared/data/db_guard.dart';
import 'package:eigen_engine/shared/data/models/player_info.dart';

/// Repository for fetching public player identities.
///
/// Uses the `app_players` RPC, which covers both human users and bots via a
/// UNION. All data is public-safe (no email, no payment tier).
class PlayerRepository {
  PlayerRepository(this._client);

  final SupabaseClient _client;

  /// Fetches public identity for any player (human or bot) by ID.
  Future<PlayerInfo> getPlayer(String id) async {
    final response = await dbGuard(
      () => _client.rpc(
        'app_players',
        params: {
          'p_ids': [id],
        },
      ),
    );
    return PlayerInfo.fromJson((response as List).single);
  }
}
