//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'display_name_update.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DisplayNameUpdate {
  /// Returns a new [DisplayNameUpdate] instance.
  DisplayNameUpdate({

    required  this.displayName,
  });

  @JsonKey(
    
    name: r'display_name',
    required: true,
    includeIfNull: false,
  )


  final String displayName;





    @override
    bool operator ==(Object other) => identical(this, other) || other is DisplayNameUpdate &&
      other.displayName == displayName;

    @override
    int get hashCode =>
        displayName.hashCode;

  factory DisplayNameUpdate.fromJson(Map<String, dynamic> json) => _$DisplayNameUpdateFromJson(json);

  Map<String, dynamic> toJson() => _$DisplayNameUpdateToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

