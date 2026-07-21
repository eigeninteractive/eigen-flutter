//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'forfeit.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Forfeit {
  /// Returns a new [Forfeit] instance.
  Forfeit({

    required  this.seat,

     this.commandId,
  });

          // minimum: 0
  @JsonKey(
    
    name: r'seat',
    required: true,
    includeIfNull: false,
  )


  final int seat;



  @JsonKey(
    
    name: r'command_id',
    required: false,
    includeIfNull: false,
  )


  final String? commandId;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Forfeit &&
      other.seat == seat &&
      other.commandId == commandId;

    @override
    int get hashCode =>
        seat.hashCode +
        commandId.hashCode;

  factory Forfeit.fromJson(Map<String, dynamic> json) => _$ForfeitFromJson(json);

  Map<String, dynamic> toJson() => _$ForfeitToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

