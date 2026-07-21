//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/player.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'players.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Players {
  /// Returns a new [Players] instance.
  Players({

    required  this.players,
  });

  @JsonKey(
    
    name: r'players',
    required: true,
    includeIfNull: false,
  )


  final List<Player> players;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Players &&
      other.players == players;

    @override
    int get hashCode =>
        players.hashCode;

  factory Players.fromJson(Map<String, dynamic> json) => _$PlayersFromJson(json);

  Map<String, dynamic> toJson() => _$PlayersToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

