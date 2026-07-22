//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'created.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Created {
  /// Returns a new [Created] instance.
  Created({required this.gameId, required this.shortCode});

  @JsonKey(name: r'game_id', required: true, includeIfNull: false)
  final String gameId;

  @JsonKey(name: r'short_code', required: true, includeIfNull: false)
  final String shortCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Created &&
          other.gameId == gameId &&
          other.shortCode == shortCode;

  @override
  int get hashCode => gameId.hashCode + shortCode.hashCode;

  factory Created.fromJson(Map<String, dynamic> json) =>
      _$CreatedFromJson(json);

  Map<String, dynamic> toJson() => _$CreatedToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
