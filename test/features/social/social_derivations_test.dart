import 'package:checks/checks.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/social/data/models/friendship.dart';
import 'package:eigen_engine/features/social/providers/social_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/container.dart';

Friendship _f(String friendId, String initiatedBy, RelationshipStatus status) =>
    Friendship(
      userId: 'me',
      friendId: friendId,
      status: status,
      initiatedBy: initiatedBy,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

/// Overrides the persistence/auth-backed [Friendships] build with fixed data.
class _FakeFriendships extends Friendships {
  _FakeFriendships(this._data);

  final List<Friendship> _data;

  @override
  Future<List<Friendship>> build() async => _data;
}

void main() {
  group('computeFriendStatus', () {
    final accepted = [_f('x', 'me', RelationshipStatus.accepted)];
    final incoming = [_f('y', 'y', RelationshipStatus.pending)];
    final sent = [_f('z', 'me', RelationshipStatus.pending)];

    test('friends when an accepted friendship matches', () {
      check(
        computeFriendStatus(accepted, incoming, sent, 'x'),
      ).equals(FriendStatus.friends);
    });

    test('incomingPending when they initiated', () {
      check(
        computeFriendStatus(accepted, incoming, sent, 'y'),
      ).equals(FriendStatus.incomingPending);
    });

    test('outgoingPending when we initiated', () {
      check(
        computeFriendStatus(accepted, incoming, sent, 'z'),
      ).equals(FriendStatus.outgoingPending);
    });

    test('none when no relationship exists', () {
      check(
        computeFriendStatus(accepted, incoming, sent, 'stranger'),
      ).equals(FriendStatus.none);
    });
  });

  group('derived friendship providers (override the immediate dependency)', () {
    final all = [
      _f('alice', 'me', RelationshipStatus.accepted),
      _f('bob', 'bob', RelationshipStatus.pending),
      _f('carol', 'me', RelationshipStatus.pending),
    ];

    ProviderContainer build() => makeContainer(
      overrides: [
        friendshipsProvider.overrideWith(() => _FakeFriendships(all)),
        currentUserIdProvider.overrideWithValue('me'),
      ],
    );

    test('acceptedFriends keeps only accepted', () async {
      check(
        await build().read(acceptedFriendsProvider.future),
      ).deepEquals([all[0]]);
    });

    test('pendingRequests keeps requests we received', () async {
      check(
        await build().read(pendingRequestsProvider.future),
      ).deepEquals([all[1]]);
    });

    test('sentRequests keeps requests we sent', () async {
      check(
        await build().read(sentRequestsProvider.future),
      ).deepEquals([all[2]]);
    });
  });
}
