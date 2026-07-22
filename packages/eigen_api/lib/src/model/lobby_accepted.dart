//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/roster.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'lobby_accepted.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class LobbyAccepted {
  /// Returns a new [LobbyAccepted] instance.
  LobbyAccepted({required this.roster});

  @JsonKey(name: r'roster', required: true, includeIfNull: false)
  final Roster roster;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LobbyAccepted && other.roster == roster;

  @override
  int get hashCode => roster.hashCode;

  factory LobbyAccepted.fromJson(Map<String, dynamic> json) =>
      _$LobbyAcceptedFromJson(json);

  Map<String, dynamic> toJson() => _$LobbyAcceptedToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
