//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'username_updated.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class UsernameUpdated {
  /// Returns a new [UsernameUpdated] instance.
  UsernameUpdated({required this.username});

  @JsonKey(name: r'username', required: true, includeIfNull: false)
  final String username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsernameUpdated && other.username == username;

  @override
  int get hashCode => username.hashCode;

  factory UsernameUpdated.fromJson(Map<String, dynamic> json) =>
      _$UsernameUpdatedFromJson(json);

  Map<String, dynamic> toJson() => _$UsernameUpdatedToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
