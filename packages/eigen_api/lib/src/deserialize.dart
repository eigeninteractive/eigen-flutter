import 'package:eigen_api/src/model/action.dart';
import 'package:eigen_api/src/model/add_bot.dart';
import 'package:eigen_api/src/model/bot.dart';
import 'package:eigen_api/src/model/bot_action.dart';
import 'package:eigen_api/src/model/bots.dart';
import 'package:eigen_api/src/model/command_accepted.dart';
import 'package:eigen_api/src/model/create_game.dart';
import 'package:eigen_api/src/model/create_solo.dart';
import 'package:eigen_api/src/model/created.dart';
import 'package:eigen_api/src/model/device_registration.dart';
import 'package:eigen_api/src/model/display_name_update.dart';
import 'package:eigen_api/src/model/display_name_updated.dart';
import 'package:eigen_api/src/model/error_response.dart';
import 'package:eigen_api/src/model/forfeit.dart';
import 'package:eigen_api/src/model/frame.dart';
import 'package:eigen_api/src/model/frames.dart';
import 'package:eigen_api/src/model/friend.dart';
import 'package:eigen_api/src/model/friend_request.dart';
import 'package:eigen_api/src/model/friend_request_result.dart';
import 'package:eigen_api/src/model/friend_requests.dart';
import 'package:eigen_api/src/model/friend_target.dart';
import 'package:eigen_api/src/model/friends.dart';
import 'package:eigen_api/src/model/friends_games.dart';
import 'package:eigen_api/src/model/game_summary.dart';
import 'package:eigen_api/src/model/health.dart';
import 'package:eigen_api/src/model/join.dart';
import 'package:eigen_api/src/model/join_by_code.dart';
import 'package:eigen_api/src/model/joined.dart';
import 'package:eigen_api/src/model/lobby.dart';
import 'package:eigen_api/src/model/lobby_accepted.dart';
import 'package:eigen_api/src/model/lobby_command.dart';
import 'package:eigen_api/src/model/my_games.dart';
import 'package:eigen_api/src/model/outcome.dart';
import 'package:eigen_api/src/model/player.dart';
import 'package:eigen_api/src/model/player_games.dart';
import 'package:eigen_api/src/model/players.dart';
import 'package:eigen_api/src/model/profile.dart';
import 'package:eigen_api/src/model/rating.dart';
import 'package:eigen_api/src/model/rating_delta.dart';
import 'package:eigen_api/src/model/rating_history.dart';
import 'package:eigen_api/src/model/rating_history_entry.dart';
import 'package:eigen_api/src/model/rating_identity.dart';
import 'package:eigen_api/src/model/ratings.dart';
import 'package:eigen_api/src/model/roster.dart';
import 'package:eigen_api/src/model/seat.dart';
import 'package:eigen_api/src/model/solo_started.dart';
import 'package:eigen_api/src/model/user_search.dart';
import 'package:eigen_api/src/model/username_update.dart';
import 'package:eigen_api/src/model/username_updated.dart';

final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

ReturnType deserialize<ReturnType, BaseType>(
  dynamic value,
  String targetType, {
  bool growable = true,
}) {
  switch (targetType) {
    case 'String':
      return '$value' as ReturnType;
    case 'int':
      return (value is int ? value : int.parse('$value')) as ReturnType;
    case 'bool':
      if (value is bool) {
        return value as ReturnType;
      }
      final valueString = '$value'.toLowerCase();
      return (valueString == 'true' || valueString == '1') as ReturnType;
    case 'double':
      return (value is double ? value : double.parse('$value')) as ReturnType;
    case 'Action':
      return Action.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'AddBot':
      return AddBot.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Bot':
      return Bot.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'BotAction':
      return BotAction.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Bots':
      return Bots.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'CommandAccepted':
      return CommandAccepted.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'CreateGame':
      return CreateGame.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'CreateSolo':
      return CreateSolo.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Created':
      return Created.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'DeviceRegistration':
      return DeviceRegistration.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'DisplayNameUpdate':
      return DisplayNameUpdate.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'DisplayNameUpdated':
      return DisplayNameUpdated.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ErrorCode':
    case 'ErrorResponse':
      return ErrorResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'Forfeit':
      return Forfeit.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Frame':
      return Frame.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Frames':
      return Frames.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Friend':
      return Friend.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'FriendRequest':
      return FriendRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'FriendRequestResult':
      return FriendRequestResult.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'FriendRequests':
      return FriendRequests.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'FriendTarget':
      return FriendTarget.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Friends':
      return Friends.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'FriendsGames':
      return FriendsGames.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'GameAccess':
    case 'GameStatus':
    case 'GameSummary':
      return GameSummary.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Health':
      return Health.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Join':
      return Join.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'JoinByCode':
      return JoinByCode.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Joined':
      return Joined.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Lobby':
      return Lobby.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'LobbyAccepted':
      return LobbyAccepted.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'LobbyCommand':
      return LobbyCommand.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'MyGames':
      return MyGames.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Outcome':
      return Outcome.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Player':
      return Player.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'PlayerGames':
      return PlayerGames.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Players':
      return Players.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Profile':
      return Profile.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Rating':
      return Rating.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'RatingDelta':
      return RatingDelta.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'RatingHistory':
      return RatingHistory.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'RatingHistoryEntry':
      return RatingHistoryEntry.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'RatingIdentity':
      return RatingIdentity.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'Ratings':
      return Ratings.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Roster':
      return Roster.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Seat':
      return Seat.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'SoloStarted':
      return SoloStarted.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'UserSearch':
      return UserSearch.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'UsernameUpdate':
      return UsernameUpdate.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'UsernameUpdated':
      return UsernameUpdated.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    default:
      RegExpMatch? match;

      if (value is List && (match = _regList.firstMatch(targetType)) != null) {
        targetType = match![1]!; // ignore: parameter_assignments
        return value
                .map<BaseType>(
                  (dynamic v) => deserialize<BaseType, BaseType>(
                    v,
                    targetType,
                    growable: growable,
                  ),
                )
                .toList(growable: growable)
            as ReturnType;
      }
      if (value is Set && (match = _regSet.firstMatch(targetType)) != null) {
        targetType = match![1]!; // ignore: parameter_assignments
        return value
                .map<BaseType>(
                  (dynamic v) => deserialize<BaseType, BaseType>(
                    v,
                    targetType,
                    growable: growable,
                  ),
                )
                .toSet()
            as ReturnType;
      }
      if (value is Map && (match = _regMap.firstMatch(targetType)) != null) {
        targetType = match![1]!.trim(); // ignore: parameter_assignments
        return Map<String, BaseType>.fromIterables(
              value.keys as Iterable<String>,
              value.values.map(
                (dynamic v) => deserialize<BaseType, BaseType>(
                  v,
                  targetType,
                  growable: growable,
                ),
              ),
            )
            as ReturnType;
      }
      break;
  }
  throw Exception('Cannot deserialize');
}
