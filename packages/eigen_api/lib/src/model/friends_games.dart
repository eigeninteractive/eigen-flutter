//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/game_summary.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'friends_games.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FriendsGames {
  /// Returns a new [FriendsGames] instance.
  FriendsGames({required this.games});

  @JsonKey(name: r'games', required: true, includeIfNull: false)
  final List<GameSummary> games;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FriendsGames && other.games == games;

  @override
  int get hashCode => games.hashCode;

  factory FriendsGames.fromJson(Map<String, dynamic> json) =>
      _$FriendsGamesFromJson(json);

  Map<String, dynamic> toJson() => _$FriendsGamesToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
