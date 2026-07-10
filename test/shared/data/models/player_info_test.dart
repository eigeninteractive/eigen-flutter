import 'package:checks/checks.dart';
import 'package:eigen_engine/shared/data/models/player_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PlayerInfo round-trips through JSON with snake_case keys', () {
    final json = <String, Object?>{
      'id': 'p1',
      'username': 'alice',
      'display_name': 'Alice',
      'avatar_url': 'https://cdn.example/a.png',
      'is_guest': true,
    };
    check(PlayerInfo.fromJson(json).toJson()).deepEquals(json);
  });

  test('decoding without is_guest fails loudly (no fail-open default)', () {
    final json = <String, Object?>{
      'id': 'p1',
      'username': 'alice',
      'display_name': 'Alice',
    };
    check(() => PlayerInfo.fromJson(json)).throws<TypeError>();
  });

  test('copyWith produces an equal-by-value instance', () {
    const player = PlayerInfo(
      id: '1',
      username: 'u',
      displayName: 'U',
      isGuest: false,
    );
    check(player.copyWith(displayName: 'U2')).equals(
      const PlayerInfo(
        id: '1',
        username: 'u',
        displayName: 'U2',
        isGuest: false,
      ),
    );
  });
}
