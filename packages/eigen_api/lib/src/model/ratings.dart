//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/rating.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'ratings.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Ratings {
  /// Returns a new [Ratings] instance.
  Ratings({required this.ratings});

  @JsonKey(name: r'ratings', required: true, includeIfNull: false)
  final List<Rating> ratings;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Ratings && other.ratings == ratings;

  @override
  int get hashCode => ratings.hashCode;

  factory Ratings.fromJson(Map<String, dynamic> json) =>
      _$RatingsFromJson(json);

  Map<String, dynamic> toJson() => _$RatingsToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
