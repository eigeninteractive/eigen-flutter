//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'join_by_code.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class JoinByCode {
  /// Returns a new [JoinByCode] instance.
  JoinByCode({

    required  this.clientSchemaVersion,

     this.commandId,

    required  this.shortCode,
  });

  @JsonKey(
    
    name: r'client_schema_version',
    required: true,
    includeIfNull: false,
  )


  final int clientSchemaVersion;



  @JsonKey(
    
    name: r'command_id',
    required: false,
    includeIfNull: false,
  )


  final String? commandId;



  @JsonKey(
    
    name: r'short_code',
    required: true,
    includeIfNull: false,
  )


  final String shortCode;





    @override
    bool operator ==(Object other) => identical(this, other) || other is JoinByCode &&
      other.clientSchemaVersion == clientSchemaVersion &&
      other.commandId == commandId &&
      other.shortCode == shortCode;

    @override
    int get hashCode =>
        clientSchemaVersion.hashCode +
        commandId.hashCode +
        shortCode.hashCode;

  factory JoinByCode.fromJson(Map<String, dynamic> json) => _$JoinByCodeFromJson(json);

  Map<String, dynamic> toJson() => _$JoinByCodeToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

