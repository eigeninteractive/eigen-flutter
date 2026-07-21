import 'dart:async';

import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/analytics/analytics_provider.dart';
import 'package:eigen_flutter/core/api/engine_api_providers.dart';
import 'package:eigen_flutter/core/storage/storage_provider.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:eigen_flutter/features/social/data/social_repository.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:riverpod_annotation/experimental/json_persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'social_providers.g.dart';

@Riverpod(keepAlive: true)
SocialRepository socialRepository(Ref ref) {
  return SocialRepository(ref.watch(socialApiProvider));
}

/// The caller's accepted friends.
///
/// Persisted: the friend list is stable, and rendering it from cache on cold
/// start avoids a spinner on a screen that rarely changes between sessions.
@Riverpod(keepAlive: true)
@JsonPersist()
class Friends extends _$Friends {
  static final send = Mutation<void>(label: 'sendFriendRequest');
  static final accept = Mutation<void>(label: 'acceptFriendRequest');
  static final remove = Mutation<void>(label: 'removeFriend');

  @override
  Future<List<Friend>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) throw StateError('User not authenticated');

    persist(
      ref.watch(storageProvider.future),
      key: friendshipsCacheKey(user.id),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        // Cache-schema version for the persisted list. Bumped to 2 when the
        // hand-written Friendship was replaced by the generated Friend, whose
        // shape carries the other user's identity rather than a pair of ids.
        destroyKey: '2',
      ),
    );

    return ref.watch(socialRepositoryProvider).getFriends();
  }

  /// Sends a request, or accepts one already pending from that user.
  ///
  /// Both lists are invalidated because either outcome is possible: the server
  /// auto-accepts when the target already had a request out to the caller, so
  /// this can add a friend rather than a pending request.
  Future<void> sendRequest(String targetUserId) async {
    await ref.read(socialRepositoryProvider).sendFriendRequest(targetUserId);
    unawaited(ref.read(analyticsServiceProvider).friendRequestSent());
    _invalidateAll();
  }

  Future<void> acceptRequest(String targetUserId) async {
    await ref.read(socialRepositoryProvider).acceptFriendRequest(targetUserId);
    unawaited(ref.read(analyticsServiceProvider).friendAccepted());
    _invalidateAll();
  }

  /// Unfriends, withdraws an outgoing request, or declines an incoming one.
  Future<void> removeFriend(String targetUserId) async {
    await ref.read(socialRepositoryProvider).removeFriend(targetUserId);
    _invalidateAll();
  }

  void _invalidateAll() {
    ref.invalidateSelf();
    ref.invalidate(friendRequestsProvider);
  }
}

/// Pending requests in both directions.
///
/// Not persisted: unlike the friend list these are short-lived, and showing a
/// stale request that has since been accepted or withdrawn is worse than a
/// brief spinner.
@riverpod
Future<List<FriendRequest>> friendRequests(Ref ref) {
  return ref.watch(socialRepositoryProvider).getFriendRequests();
}

/// Requests the caller received and can act on.
@riverpod
Future<List<FriendRequest>> incomingRequests(Ref ref) async {
  final requests = await ref.watch(friendRequestsProvider.future);
  return requests
      .where((r) => r.direction == FriendRequestDirectionEnum.incoming)
      .toList();
}

/// Requests the caller sent and can withdraw.
@riverpod
Future<List<FriendRequest>> outgoingRequests(Ref ref) async {
  final requests = await ref.watch(friendRequestsProvider.future);
  return requests
      .where((r) => r.direction == FriendRequestDirectionEnum.outgoing)
      .toList();
}

/// Joinable games created by the caller's friends.
@riverpod
Future<List<GameSummary>> friendsGames(Ref ref) {
  return ref.watch(socialRepositoryProvider).getFriendsGames();
}

/// The current relationship between the local user and another player.
enum FriendStatus { friends, incomingPending, outgoingPending, none }

/// Derives the relationship with [targetId] from the friends and requests
/// lists.
///
/// Blocks are deliberately absent: a blocked user is filtered out of search and
/// cannot appear as a target here, so there is no state to render for them.
FriendStatus computeFriendStatus(
  List<Friend> friends,
  List<FriendRequest> requests,
  String targetId,
) {
  if (friends.any((f) => f.userId == targetId)) return FriendStatus.friends;
  for (final request in requests) {
    if (request.userId != targetId) continue;
    return request.direction == FriendRequestDirectionEnum.incoming
        ? FriendStatus.incomingPending
        : FriendStatus.outgoingPending;
  }
  return FriendStatus.none;
}

@riverpod
Future<FriendStatus> friendStatus(Ref ref, {required String targetId}) async {
  final friends = await ref.watch(friendsProvider.future);
  final requests = await ref.watch(friendRequestsProvider.future);
  return computeFriendStatus(friends, requests, targetId);
}
