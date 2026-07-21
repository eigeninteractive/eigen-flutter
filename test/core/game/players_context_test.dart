import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/game/game_player.dart';
import 'package:eigen_flutter/core/game/my_seat.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/game/players_context.dart';
import 'package:flutter_test/flutter_test.dart';

final _alice = GamePlayer(
  playerIndex: 0,
  type: SeatTypeEnum.human,
  info: Player(
    id: '1',
    username: 'alice',
    displayName: 'Alice',
    avatarUrl: null,
    isAnonymous: false,
  ),
);
final _bob = GamePlayer(
  playerIndex: 1,
  type: SeatTypeEnum.bot,
  info: Player(
    id: '2',
    username: 'bob',
    displayName: 'Bob',
    avatarUrl: null,
    isAnonymous: false,
  ),
);

void main() {
  test('operator[] resolves the seated player', () {
    final ctx = PlayersContext(
      players: {0: _alice, 1: _bob},
      mySeat: Seated(0),
    );
    check(ctx[0]).identicalTo(_alice);
    check(ctx[1]).identicalTo(_bob);
  });

  test('me resolves the current user when Seated', () {
    final ctx = PlayersContext(
      players: {0: _alice, 1: _bob},
      mySeat: Seated(1),
    );
    check(ctx.me).identicalTo(_bob);
  });

  test('me is null for a Viewer (non-participant, no seat)', () {
    final ctx = PlayersContext(players: {0: _alice}, mySeat: Viewer());
    check(ctx.me).isNull();
  });

  test('mySeat.indexOrNull is the seat when Seated, null for a Viewer', () {
    check(const Seated(2).indexOrNull).equals(2);
    check(const Viewer().indexOrNull).isNull();
  });
}
