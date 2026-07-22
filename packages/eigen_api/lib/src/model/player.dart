//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'player.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Player {
  /// Returns a new [Player] instance.
  Player({
    required this.id,

    required this.username,

    required this.displayName,

    required this.avatarUrl,

    required this.isAnonymous,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'username', required: true, includeIfNull: false)
  final String username;

  @JsonKey(name: r'display_name', required: true, includeIfNull: false)
  final String displayName;

  @JsonKey(name: r'avatar_url', required: true, includeIfNull: true)
  final String? avatarUrl;

  @JsonKey(name: r'is_anonymous', required: true, includeIfNull: false)
  final bool isAnonymous;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Player &&
          other.id == id &&
          other.username == username &&
          other.displayName == displayName &&
          other.avatarUrl == avatarUrl &&
          other.isAnonymous == isAnonymous;

  @override
  int get hashCode =>
      id.hashCode +
      username.hashCode +
      displayName.hashCode +
      (avatarUrl == null ? 0 : avatarUrl.hashCode) +
      isAnonymous.hashCode;

  factory Player.fromJson(Map<String, dynamic> json) => _$PlayerFromJson(json);

  Map<String, dynamic> toJson() => _$PlayerToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
