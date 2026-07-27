import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/features/social/providers/social_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FriendRequest request(FriendRequestDirectionEnum direction) => FriendRequest(
    username: 'player',
    displayName: 'Player',
    avatarUrl: null,
    isAnonymous: false,
    userId: 'target',
    since: 1,
    direction: direction,
  );

  test('unknown friend-request direction does not expose a wrong action', () {
    final status = computeFriendStatus(const [], [
      request(FriendRequestDirectionEnum.unknownDefaultOpenApi),
    ], 'target');

    expect(status, FriendStatus.updateRequired);
  });

  test('known friend-request directions retain their actions', () {
    expect(
      computeFriendStatus(const [], [
        request(FriendRequestDirectionEnum.incoming),
      ], 'target'),
      FriendStatus.incomingPending,
    );
    expect(
      computeFriendStatus(const [], [
        request(FriendRequestDirectionEnum.outgoing),
      ], 'target'),
      FriendStatus.outgoingPending,
    );
  });
}
