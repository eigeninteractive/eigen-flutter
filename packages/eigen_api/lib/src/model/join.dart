//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'join.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Join {
  /// Returns a new [Join] instance.
  Join({required this.clientSchemaVersion, this.commandId});

  @JsonKey(name: r'client_schema_version', required: true, includeIfNull: false)
  final int clientSchemaVersion;

  @JsonKey(name: r'command_id', required: false, includeIfNull: false)
  final String? commandId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Join &&
          other.clientSchemaVersion == clientSchemaVersion &&
          other.commandId == commandId;

  @override
  int get hashCode => clientSchemaVersion.hashCode + commandId.hashCode;

  factory Join.fromJson(Map<String, dynamic> json) => _$JoinFromJson(json);

  Map<String, dynamic> toJson() => _$JoinToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
