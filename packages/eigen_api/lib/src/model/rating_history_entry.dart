//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rating_history_entry.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class RatingHistoryEntry {
  /// Returns a new [RatingHistoryEntry] instance.
  RatingHistoryEntry({
    required this.gameId,

    required this.pool,

    required this.displayBefore,

    required this.displayAfter,

    required this.displayChange,

    required this.createdAt,
  });

  @JsonKey(name: r'game_id', required: true, includeIfNull: false)
  final String gameId;

  @JsonKey(name: r'pool', required: true, includeIfNull: false)
  final String pool;

  @JsonKey(name: r'display_before', required: true, includeIfNull: false)
  final int displayBefore;

  @JsonKey(name: r'display_after', required: true, includeIfNull: false)
  final int displayAfter;

  @JsonKey(name: r'display_change', required: true, includeIfNull: false)
  final int displayChange;

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final int createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RatingHistoryEntry &&
          other.gameId == gameId &&
          other.pool == pool &&
          other.displayBefore == displayBefore &&
          other.displayAfter == displayAfter &&
          other.displayChange == displayChange &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      gameId.hashCode +
      pool.hashCode +
      displayBefore.hashCode +
      displayAfter.hashCode +
      displayChange.hashCode +
      createdAt.hashCode;

  factory RatingHistoryEntry.fromJson(Map<String, dynamic> json) =>
      _$RatingHistoryEntryFromJson(json);

  Map<String, dynamic> toJson() => _$RatingHistoryEntryToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
