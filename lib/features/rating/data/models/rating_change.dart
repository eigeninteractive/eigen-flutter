import 'package:freezed_annotation/freezed_annotation.dart';

part 'rating_change.freezed.dart';
part 'rating_change.g.dart';

/// A single rating change entry from the `rating_history` table.
///
/// Represents the before/after delta for one player in one rated game.
@freezed
abstract class RatingChange with _$RatingChange {
  const factory RatingChange({
    required String gameId,
    required String pool,
    required int displayBefore,
    required int displayAfter,

    /// Signed change: positive = gained rating, negative = lost.
    required int displayChange,

    required DateTime createdAt,
  }) = _RatingChange;

  factory RatingChange.fromJson(Map<String, dynamic> json) =>
      _$RatingChangeFromJson(json);
}
