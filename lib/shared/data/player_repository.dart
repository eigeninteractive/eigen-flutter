import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/engine_call.dart';

/// Thrown when a player lookup matches no row.
///
/// Purged accounts leave no identity behind, so reaching this usually means a
/// synthetic deleted-seat placeholder id (see `GamePlayer.isDeleted`) leaked
/// into an identity lookup.
class PlayerNotFoundException implements Exception {
  const PlayerNotFoundException(this.playerId);

  /// The id that matched no player.
  final String playerId;

  @override
  String toString() => 'No player found for id: $playerId';
}

/// Fetches public player identities, humans and bots alike.
///
/// The batch endpoint is the decided alternative to denormalising identity onto
/// game rows: a caller collects the ids it needs and resolves them in one
/// request, and the client's persisted cache absorbs the repeats.
///
/// This is the batch itself; single-id resolution is [PlayerBatchLoader]'s job,
/// which coalesces per-id cache misses back into one call here. Nothing calls a
/// per-id method on this repository; that would be the N+1 the endpoint exists
/// to avoid.
///
/// Everything returned is public-safe: no email, no account state.
class PlayerRepository {
  PlayerRepository(this._api);

  final PlayersApi _api;

  /// Public identities for a batch of ids.
  ///
  /// Ids that match nothing are simply absent, so the result may be shorter
  /// than [ids]; a purged account is a normal outcome here, not an error. An
  /// empty [ids] resolves without a request.
  Future<List<Player>> getPlayers(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final body = await engineData(() => _api.getPlayers(ids: ids.join(',')));
    return body.players;
  }
}
