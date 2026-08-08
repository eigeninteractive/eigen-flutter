import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/engine_call.dart';

/// Player ratings and the caller's own rating log.
///
/// Ratings are computed server-side inside the finish transaction and
/// delivered to a live game as a post-finish transition; this repository only
/// reads the settled values.
class RatingRepository {
  RatingRepository(this._me, this._players);

  final MeApi _me;
  final PlayersApi _players;

  /// Every pool [playerId] has played in, best rating first.
  ///
  /// Works for humans and bots alike: a rating row is keyed by exactly one of
  /// the two, so the id alone is enough. Display ratings are public.
  Future<List<Rating>> getPlayerRatings(String playerId) async {
    final body = await engineData(
      () => _players.getPlayerRatings(playerId: playerId),
    );
    return body.ratings;
  }

  /// The caller's own ratings.
  ///
  /// Distinct from [getPlayerRatings] only in that it needs no id; the token
  /// identifies the caller.
  Future<List<Rating>> getMyRatings() async {
    final body = await engineData(() => _me.getMyRatings());
    return body.ratings;
  }

  /// The caller's rating changes, newest first, optionally for one [pool].
  Future<List<RatingHistoryEntry>> getMyRatingHistory({
    String? pool,
    int? limit,
  }) async {
    final body = await engineData(
      () => _me.getMyRatingHistory(pool: pool, limit: limit),
    );
    return body.history;
  }
}
