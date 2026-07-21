//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/frame.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'command_accepted.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CommandAccepted {
  /// Returns a new [CommandAccepted] instance.
  CommandAccepted({

    required  this.version,

    required  this.frame,
  });

  @JsonKey(
    
    name: r'version',
    required: true,
    includeIfNull: false,
  )


  final int version;



  @JsonKey(
    
    name: r'frame',
    required: true,
    includeIfNull: false,
  )


  final Frame frame;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CommandAccepted &&
      other.version == version &&
      other.frame == frame;

    @override
    int get hashCode =>
        version.hashCode +
        frame.hashCode;

  factory CommandAccepted.fromJson(Map<String, dynamic> json) => _$CommandAcceptedFromJson(json);

  Map<String, dynamic> toJson() => _$CommandAcceptedToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

