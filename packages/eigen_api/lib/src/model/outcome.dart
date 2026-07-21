//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'outcome.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Outcome {
  /// Returns a new [Outcome] instance.
  Outcome({

    required  this.playerIndex,

    required  this.result,

    required  this.placement,

    required  this.teamIndex,

     this.score,
  });

  @JsonKey(
    
    name: r'player_index',
    required: true,
    includeIfNull: false,
  )


  final int playerIndex;



  @JsonKey(
    
    name: r'result',
    required: true,
    includeIfNull: false,
  )


  final OutcomeResultEnum result;



  @JsonKey(
    
    name: r'placement',
    required: true,
    includeIfNull: false,
  )


  final int placement;



  @JsonKey(
    
    name: r'team_index',
    required: true,
    includeIfNull: false,
  )


  final int teamIndex;



  @JsonKey(
    
    name: r'score',
    required: false,
    includeIfNull: false,
  )


  final num? score;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Outcome &&
      other.playerIndex == playerIndex &&
      other.result == result &&
      other.placement == placement &&
      other.teamIndex == teamIndex &&
      other.score == score;

    @override
    int get hashCode =>
        playerIndex.hashCode +
        result.hashCode +
        placement.hashCode +
        teamIndex.hashCode +
        (score == null ? 0 : score.hashCode);

  factory Outcome.fromJson(Map<String, dynamic> json) => _$OutcomeFromJson(json);

  Map<String, dynamic> toJson() => _$OutcomeToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum OutcomeResultEnum {
@JsonValue(r'win')
win(r'win'),
@JsonValue(r'loss')
loss(r'loss'),
@JsonValue(r'draw')
draw(r'draw'),
@JsonValue(r'eliminated')
eliminated(r'eliminated');

const OutcomeResultEnum(this.value);

final String value;

@override
String toString() => value;
}


