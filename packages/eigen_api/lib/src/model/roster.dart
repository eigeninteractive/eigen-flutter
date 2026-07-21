//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/seat.dart';
import 'package:eigen_api/src/model/game_status.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'roster.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Roster {
  /// Returns a new [Roster] instance.
  Roster({

    required  this.type,

    required  this.status,

    required  this.players,
  });

  @JsonKey(
    
    name: r'type',
    required: true,
    includeIfNull: false,
  )


  final RosterTypeEnum type;



  @JsonKey(
    
    name: r'status',
    required: true,
    includeIfNull: false,
  )


  final GameStatus status;



  @JsonKey(
    
    name: r'players',
    required: true,
    includeIfNull: false,
  )


  final List<Seat> players;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Roster &&
      other.type == type &&
      other.status == status &&
      other.players == players;

    @override
    int get hashCode =>
        type.hashCode +
        status.hashCode +
        players.hashCode;

  factory Roster.fromJson(Map<String, dynamic> json) => _$RosterFromJson(json);

  Map<String, dynamic> toJson() => _$RosterToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum RosterTypeEnum {
@JsonValue(r'roster')
roster(r'roster');

const RosterTypeEnum(this.value);

final String value;

@override
String toString() => value;
}


