import 'package:checks/checks.dart';
import 'package:eigen_engine/core/game/game_player.dart';
import 'package:eigen_engine/core/game/participant_type.dart';
import 'package:eigen_engine/core/game/players_context.dart';
import 'package:eigen_engine/shared/data/models/player_info.dart';
import 'package:flutter_test/flutter_test.dart';

const _alice = GamePlayer(
  playerIndex: 0,
  type: ParticipantType.human,
  info: PlayerInfo(
    id: '1',
    username: 'alice',
    displayName: 'Alice',
    isGuest: false,
  ),
);
const _bob = GamePlayer(
  playerIndex: 1,
  type: ParticipantType.bot,
  info: PlayerInfo(
    id: '2',
    username: 'bob',
    displayName: 'Bob',
    isGuest: false,
  ),
);

void main() {
  test('operator[] resolves the seated player', () {
    const ctx = PlayersContext(players: {0: _alice, 1: _bob}, myPlayerIndex: 0);
    check(ctx[0]).identicalTo(_alice);
    check(ctx[1]).identicalTo(_bob);
  });

  test('me delegates to myPlayerIndex', () {
    const ctx = PlayersContext(players: {0: _alice, 1: _bob}, myPlayerIndex: 1);
    check(ctx.me).identicalTo(_bob);
  });

  test('me throws for a spectator (index -1, no seat)', () {
    const ctx = PlayersContext(players: {0: _alice}, myPlayerIndex: -1);
    check(() => ctx.me).throws<Error>();
  });
}
