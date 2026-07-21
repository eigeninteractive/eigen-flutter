//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/frame.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'solo_started.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SoloStarted {
  /// Returns a new [SoloStarted] instance.
  SoloStarted({

    required  this.gameId,

    required  this.shortCode,

    required  this.version,

    required  this.frame,
  });

  @JsonKey(
    
    name: r'game_id',
    required: true,
    includeIfNull: false,
  )


  final String gameId;



  @JsonKey(
    
    name: r'short_code',
    required: true,
    includeIfNull: false,
  )


  final String shortCode;



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
    bool operator ==(Object other) => identical(this, other) || other is SoloStarted &&
      other.gameId == gameId &&
      other.shortCode == shortCode &&
      other.version == version &&
      other.frame == frame;

    @override
    int get hashCode =>
        gameId.hashCode +
        shortCode.hashCode +
        version.hashCode +
        frame.hashCode;

  factory SoloStarted.fromJson(Map<String, dynamic> json) => _$SoloStartedFromJson(json);

  Map<String, dynamic> toJson() => _$SoloStartedToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

