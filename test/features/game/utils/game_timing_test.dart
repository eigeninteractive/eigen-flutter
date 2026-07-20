import 'package:checks/checks.dart';
import 'package:eigen_flutter/features/game/data/models/game.dart';
import 'package:eigen_flutter/core/game/game_status.dart';
import 'package:eigen_flutter/features/game/utils/game_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Game _game({int? turnSeconds, int? budgetSeconds, int? incrementSeconds}) =>
    Game(
      id: 'g',
      status: GameStatus.active,
      access: GameAccess.public,
      turnSeconds: turnSeconds,
      budgetSeconds: budgetSeconds,
      incrementSeconds: incrementSeconds,
      minPlayers: 2,
      maxPlayers: 2,
      config: const {},
      schemaVersion: 1,
      rated: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('gameTimingLabel', () {
    test('untimed when no turn or budget', () {
      check(gameTimingLabel(_game())).equals('untimed');
    });

    test('per-turn thresholds', () {
      check(gameTimingLabel(_game(turnSeconds: 30))).equals('30s/turn');
      check(gameTimingLabel(_game(turnSeconds: 300))).equals('5m/turn');
      check(gameTimingLabel(_game(turnSeconds: 3600))).equals('1h/turn');
      check(gameTimingLabel(_game(turnSeconds: 86400))).equals('1d/turn');
    });

    test('budget mode with and without increment', () {
      check(gameTimingLabel(_game(budgetSeconds: 600))).equals('10m');
      check(
        gameTimingLabel(_game(budgetSeconds: 180, incrementSeconds: 2)),
      ).equals('3m+2s');
    });
  });

  group('gameTimingIcon', () {
    test('selects an icon per timing mode', () {
      check(gameTimingIcon(_game(budgetSeconds: 600))).equals(Icons.av_timer);
      check(gameTimingIcon(_game())).equals(Icons.all_inclusive);
      check(gameTimingIcon(_game(turnSeconds: 30))).equals(Icons.flash_on);
      check(gameTimingIcon(_game(turnSeconds: 600))).equals(Icons.speed);
      check(gameTimingIcon(_game(turnSeconds: 3600))).equals(Icons.schedule);
    });
  });

  group('formatWaitDuration', () {
    test('buckets elapsed time', () {
      final now = DateTime.now();
      check(formatWaitDuration(now)).equals('just now');
      check(
        formatWaitDuration(now.subtract(const Duration(minutes: 5))),
      ).equals('5m waiting');
      check(
        formatWaitDuration(now.subtract(const Duration(hours: 2))),
      ).equals('2h waiting');
    });
  });
}
