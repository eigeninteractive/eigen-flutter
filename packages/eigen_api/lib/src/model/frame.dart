//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/rating_delta.dart';
import 'package:eigen_api/src/model/outcome.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'frame.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Frame {
  /// Returns a new [Frame] instance.
  Frame({

    required  this.type,

    required  this.version,

    required  this.data,

    required  this.pendingPlayers,

    required  this.deadline,

    required  this.playerTimes,

     this.outcomes,

     this.ratings,
  });

  @JsonKey(
    
    name: r'type',
    required: true,
    includeIfNull: false,
  )


  final FrameTypeEnum type;



  @JsonKey(
    
    name: r'version',
    required: true,
    includeIfNull: false,
  )


  final int version;



  @JsonKey(
    
    name: r'data',
    required: true,
    includeIfNull: false,
  )


  final Object data;



  @JsonKey(
    
    name: r'pending_players',
    required: true,
    includeIfNull: false,
  )


  final List<int> pendingPlayers;



  @JsonKey(
    
    name: r'deadline',
    required: true,
    includeIfNull: true,
  )


  final int? deadline;



  @JsonKey(
    
    name: r'player_times',
    required: true,
    includeIfNull: true,
  )


  final List<int>? playerTimes;



  @JsonKey(
    
    name: r'outcomes',
    required: false,
    includeIfNull: false,
  )


  final List<Outcome>? outcomes;



  @JsonKey(
    
    name: r'ratings',
    required: false,
    includeIfNull: false,
  )


  final List<RatingDelta>? ratings;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Frame &&
      other.type == type &&
      other.version == version &&
      other.data == data &&
      other.pendingPlayers == pendingPlayers &&
      other.deadline == deadline &&
      other.playerTimes == playerTimes &&
      other.outcomes == outcomes &&
      other.ratings == ratings;

    @override
    int get hashCode =>
        type.hashCode +
        version.hashCode +
        data.hashCode +
        pendingPlayers.hashCode +
        (deadline == null ? 0 : deadline.hashCode) +
        (playerTimes == null ? 0 : playerTimes.hashCode) +
        outcomes.hashCode +
        ratings.hashCode;

  factory Frame.fromJson(Map<String, dynamic> json) => _$FrameFromJson(json);

  Map<String, dynamic> toJson() => _$FrameToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum FrameTypeEnum {
@JsonValue(r'frame')
frame(r'frame');

const FrameTypeEnum(this.value);

final String value;

@override
String toString() => value;
}


