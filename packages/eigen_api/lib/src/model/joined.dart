//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/roster.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'joined.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Joined {
  /// Returns a new [Joined] instance.
  Joined({

    required  this.gameId,

    required  this.roster,
  });

  @JsonKey(
    
    name: r'game_id',
    required: true,
    includeIfNull: false,
  )


  final String gameId;



  @JsonKey(
    
    name: r'roster',
    required: true,
    includeIfNull: false,
  )


  final Roster roster;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Joined &&
      other.gameId == gameId &&
      other.roster == roster;

    @override
    int get hashCode =>
        gameId.hashCode +
        roster.hashCode;

  factory Joined.fromJson(Map<String, dynamic> json) => _$JoinedFromJson(json);

  Map<String, dynamic> toJson() => _$JoinedToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

