//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'seat.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Seat {
  /// Returns a new [Seat] instance.
  Seat({

    required  this.playerIndex,

    required  this.userId,

    required  this.botId,

    required  this.type,
  });

  @JsonKey(
    
    name: r'player_index',
    required: true,
    includeIfNull: false,
  )


  final int playerIndex;



  @JsonKey(
    
    name: r'user_id',
    required: true,
    includeIfNull: true,
  )


  final String? userId;



  @JsonKey(
    
    name: r'bot_id',
    required: true,
    includeIfNull: true,
  )


  final String? botId;



  @JsonKey(
    
    name: r'type',
    required: true,
    includeIfNull: false,
  )


  final SeatTypeEnum type;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Seat &&
      other.playerIndex == playerIndex &&
      other.userId == userId &&
      other.botId == botId &&
      other.type == type;

    @override
    int get hashCode =>
        playerIndex.hashCode +
        (userId == null ? 0 : userId.hashCode) +
        (botId == null ? 0 : botId.hashCode) +
        type.hashCode;

  factory Seat.fromJson(Map<String, dynamic> json) => _$SeatFromJson(json);

  Map<String, dynamic> toJson() => _$SeatToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum SeatTypeEnum {
@JsonValue(r'human')
human(r'human'),
@JsonValue(r'bot')
bot(r'bot');

const SeatTypeEnum(this.value);

final String value;

@override
String toString() => value;
}


