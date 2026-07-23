import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/engine_call.dart';

/// The friend graph: friends, pending requests, blocks, and user search.
///
/// Every write is idempotent and answers 204, so retrying one is always safe.
/// The server owns the side effects a write implies - notably the friend
/// request and friend accepted pushes - so there is nothing to fan out here.
class SocialRepository {
  SocialRepository(this._api);

  final SocialApi _api;

  /// The caller's accepted friends, most recently befriended first.
  Future<List<Friend>> getFriends() async {
    final body = await engineData(() => _api.listFriends());
    return body.friends;
  }

  /// Pending requests in both directions.
  ///
  /// Each entry carries its own [FriendRequest.direction], so incoming
  /// (actionable) and outgoing (withdrawable) requests arrive together and are
  /// split by the caller rather than by two round trips.
  Future<List<FriendRequest>> getFriendRequests() async {
    final body = await engineData(() => _api.listFriendRequests());
    return body.requests;
  }

  /// Joinable games created by the caller's friends.
  ///
  /// [cursor] is the previous page's last `created_at`; omit for the first
  /// page.
  Future<List<GameSummary>> getFriendsGames({int? limit, int? cursor}) async {
    final body = await engineData(
      () => _api.getFriendsGames(limit: limit, cursor: cursor),
    );
    return body.games;
  }

  /// Case-insensitive search over usernames and display names.
  ///
  /// Excludes the caller, guests, and anyone in a blocking relationship either
  /// way. An empty query resolves without a request - this backs an
  /// autocomplete, which would otherwise fire one per keystroke on an empty
  /// field.
  Future<List<Player>> searchUsers(String query) async {
    if (query.trim().isEmpty) return const [];
    final body = await engineData(() => _api.searchUsers(q: query));
    return body.users;
  }

  /// Sends a friend request.
  ///
  /// Returns what actually happened: a request to someone who already has one
  /// pending to the caller is accepted outright rather than queued, so the
  /// caller must render the [FriendRequestResult.status] rather than assume
  /// "requested".
  Future<FriendRequestResultStatusEnum> sendFriendRequest(String userId) async {
    final body = await engineData(
      () => _api.sendFriendRequest(
        friendTarget: FriendTarget(targetUserId: userId),
      ),
    );
    return body.status;
  }

  /// Accepts a request [userId] sent the caller.
  Future<void> acceptFriendRequest(String userId) =>
      engineCall(() => _api.acceptFriendRequest(userId: userId));

  /// Unfriends, withdraws an outgoing request, or declines an incoming one -
  /// all the same operation. Never lifts a block; that is [unblockUser].
  Future<void> removeFriend(String userId) =>
      engineCall(() => _api.removeFriend(userId: userId));

  /// Blocks [userId], replacing any existing friendship or request.
  Future<void> blockUser(String userId) =>
      engineCall(() => _api.blockUser(userId: userId));

  /// Lifts a block the caller placed. Only the blocker can.
  Future<void> unblockUser(String userId) =>
      engineCall(() => _api.unblockUser(userId: userId));
}
