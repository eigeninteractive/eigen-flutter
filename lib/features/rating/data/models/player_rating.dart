import 'package:freezed_annotation/freezed_annotation.dart';

part 'player_rating.freezed.dart';
part 'player_rating.g.dart';

/// A player's OpenSkill rating in a specific rating pool.
///
/// Sourced from the `player_ratings` table via the `get_player_ratings` RPC.
@freezed
abstract class PlayerRating with _$PlayerRating {
  const factory PlayerRating({
    /// Rating pool name, e.g. 'rapid' or 'daily'.
    required String pool,

    /// OpenSkill mean skill estimate.
    required double mu,

    /// OpenSkill uncertainty (standard deviation).
    required double sigma,

    /// Conservative display rating: `max(0, round((mu - 3 * sigma) * 40))`.
    required int displayRating,
  }) = _PlayerRating;

  factory PlayerRating.fromJson(Map<String, dynamic> json) =>
      _$PlayerRatingFromJson(json);
}
