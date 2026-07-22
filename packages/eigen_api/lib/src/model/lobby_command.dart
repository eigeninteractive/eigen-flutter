//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'lobby_command.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class LobbyCommand {
  /// Returns a new [LobbyCommand] instance.
  LobbyCommand({this.commandId});

  @JsonKey(name: r'command_id', required: false, includeIfNull: false)
  final String? commandId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LobbyCommand && other.commandId == commandId;

  @override
  int get hashCode => commandId.hashCode;

  factory LobbyCommand.fromJson(Map<String, dynamic> json) =>
      _$LobbyCommandFromJson(json);

  Map<String, dynamic> toJson() => _$LobbyCommandToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
