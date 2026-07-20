import 'package:eigen_flutter/features/rating/data/models/player_rating.dart';

/// Display helpers for [PlayerRating].
extension PlayerRatingUi on PlayerRating {
  /// The pool name capitalised for display, e.g. `rapid` becomes `Rapid`.
  String get poolLabel =>
      pool.isEmpty ? pool : pool[0].toUpperCase() + pool.substring(1);
}
