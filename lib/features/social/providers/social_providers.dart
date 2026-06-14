import 'dart:async';

import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:riverpod_annotation/experimental/json_persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_engine/core/analytics/analytics_provider.dart';
import 'package:eigen_engine/core/storage/storage_provider.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/social/data/models/friendship.dart';
import 'package:eigen_engine/features/social/data/social_repository.dart';

part 'social_providers.g.dart';

@Riverpod(keepAlive: true)
SocialRepository socialRepository(Ref ref) {
  return SocialRepository(ref.watch(supabaseClientProvider));
}

@Riverpod(keepAlive: true)
@JsonPersist()
class Friendships extends _$Friendships {
  static final send = Mutation<void>(label: 'sendFriendRequest');
  static final accept = Mutation<void>(label: 'acceptFriendRequest');
  static final remove = Mutation<void>(label: 'removeFriend');

  @override
  Future<List<Friendship>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) throw StateError('User not authenticated');

    persist(
      ref.watch(storageProvider.future),
      key: friendshipsCacheKey(user.id),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        destroyKey: '1',
      ),
    );

    return ref.watch(socialRepositoryProvider).getFriendships();
  }

  Future<void> sendRequest(String targetUserId) async {
    await ref.read(socialRepositoryProvider).sendFriendRequest(targetUserId);
    unawaited(ref.read(analyticsServiceProvider).friendRequestSent());
    ref.invalidateSelf();
  }

  Future<void> acceptRequest(String targetUserId) async {
    await ref.read(socialRepositoryProvider).acceptFriendRequest(targetUserId);
    unawaited(ref.read(analyticsServiceProvider).friendAccepted());
    ref.invalidateSelf();
  }

  Future<void> removeFriend(String targetUserId) async {
    await ref.read(socialRepositoryProvider).removeFriend(targetUserId);
    ref.invalidateSelf();
  }
}

@riverpod
Future<List<Friendship>> acceptedFriends(Ref ref) async {
  final friendships = await ref.watch(friendshipsProvider.future);
  return friendships
      .where((f) => f.status == RelationshipStatus.accepted)
      .toList();
}

@riverpod
Future<List<Friendship>> pendingRequests(Ref ref) async {
  final friendships = await ref.watch(friendshipsProvider.future);
  final currentUserId = ref.watch(currentUserIdProvider);

  return friendships.where((f) {
    return f.status == RelationshipStatus.pending &&
        f.initiatedBy != currentUserId; // Only show requests we received
  }).toList();
}

@riverpod
Future<List<Friendship>> sentRequests(Ref ref) async {
  final friendships = await ref.watch(friendshipsProvider.future);
  final currentUserId = ref.watch(currentUserIdProvider);

  return friendships.where((f) {
    return f.status == RelationshipStatus.pending &&
        f.initiatedBy == currentUserId; // Requests we sent
  }).toList();
}

/// The current friendship state between the local user and another player.
enum FriendStatus { friends, incomingPending, outgoingPending, none }

/// Derives the friendship relationship status between the current user
/// and [targetId] from the three pre-filtered friendship lists.
FriendStatus computeFriendStatus(
  List<Friendship> accepted,
  List<Friendship> incoming,
  List<Friendship> sent,
  String targetId,
) {
  if (accepted.any((f) => f.friendId == targetId)) return FriendStatus.friends;
  if (incoming.any((f) => f.initiatedBy == targetId)) {
    return FriendStatus.incomingPending;
  }
  if (sent.any((f) => f.friendId == targetId)) {
    return FriendStatus.outgoingPending;
  }
  return FriendStatus.none;
}

@riverpod
Future<FriendStatus> friendStatus(Ref ref, {required String targetId}) async {
  final accepted = await ref.watch(acceptedFriendsProvider.future);
  final incoming = await ref.watch(pendingRequestsProvider.future);
  final sent = await ref.watch(sentRequestsProvider.future);
  return computeFriendStatus(accepted, incoming, sent, targetId);
}
