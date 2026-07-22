//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'action.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Action {
  /// Returns a new [Action] instance.
  Action({
    required this.seat,

    this.data,

    required this.expectedVersion,

    this.commandId,
  });

  // minimum: 0
  @JsonKey(name: r'seat', required: true, includeIfNull: false)
  final int seat;

  @JsonKey(name: r'data', required: false, includeIfNull: false)
  final Object? data;

  // minimum: 0
  @JsonKey(name: r'expected_version', required: true, includeIfNull: false)
  final int expectedVersion;

  @JsonKey(name: r'command_id', required: false, includeIfNull: false)
  final String? commandId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Action &&
          other.seat == seat &&
          other.data == data &&
          other.expectedVersion == expectedVersion &&
          other.commandId == commandId;

  @override
  int get hashCode =>
      seat.hashCode +
      (data == null ? 0 : data.hashCode) +
      expectedVersion.hashCode +
      commandId.hashCode;

  factory Action.fromJson(Map<String, dynamic> json) => _$ActionFromJson(json);

  Map<String, dynamic> toJson() => _$ActionToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
