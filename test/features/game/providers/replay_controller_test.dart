import 'package:checks/checks.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/features/game/providers/game_frame_provider.dart';
import 'package:eigen_flutter/features/game/providers/replay_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/container.dart';
import '../../../helpers/example_rules.dart';

Frame _frame(int version, int moves) => Frame(
  type: FrameTypeEnum.frame,
  version: version,
  data: {'moves': moves},
  pendingPlayers: const [0],
  deadline: null,
  playerTimes: null,
);

void main() {
  group('ReplayCursor', () {
    test('starts at the first frame', () {
      final container = makeContainer();
      final index = container.read(
        replayCursorProvider(gameId: 'g1', frameCount: 5),
      );
      check(index).equals(0);
    });

    test('next() advances but stops at the last frame', () {
      final container = makeContainer();
      final cursor = container.read(
        replayCursorProvider(gameId: 'g1', frameCount: 3).notifier,
      );

      cursor.next();
      cursor.next();
      check(cursor.state).equals(2);
      cursor.next(); // already at the last frame, so a no-op
      check(cursor.state).equals(2);
    });

    test('previous() rewinds but stops at the first frame', () {
      final container = makeContainer();
      final cursor = container.read(
        replayCursorProvider(gameId: 'g1', frameCount: 3).notifier,
      );

      cursor.jumpTo(2);
      cursor.previous();
      check(cursor.state).equals(1);
      cursor.previous();
      check(cursor.state).equals(0);
      cursor.previous(); // already at the first frame, so a no-op
      check(cursor.state).equals(0);
    });

    test('jumpTo() clamps to the valid range', () {
      final container = makeContainer();
      final cursor = container.read(
        replayCursorProvider(gameId: 'g1', frameCount: 4).notifier,
      );

      cursor.jumpTo(10);
      check(cursor.state).equals(3);
      cursor.jumpTo(-5);
      check(cursor.state).equals(0);
    });
  });

  group('replayFrameAt', () {
    test('derives a GameFrame for the given index via parseObservation', () {
      final frames = [_frame(0, 0), _frame(1, 1), _frame(2, 2)];
      final container = makeContainer(
        overrides: [
          replayFramesProvider(
            gameId: 'g1',
          ).overrideWith((ref) async => frames),
          gameRulesProvider(
            gameId: 'g1',
          ).overrideWith((ref) async => const ExampleRules()),
        ],
      );

      // Resolve the async overrides before reading the synchronous derivation.
      return container
          .read(replayFramesProvider(gameId: 'g1').future)
          .then((_) => container.read(gameRulesProvider(gameId: 'g1').future))
          .then((_) {
            final frame = container.read(
              replayFrameAtProvider(gameId: 'g1', index: 1),
            );
            check(frame).isNotNull();
            check(frame!.version).equals(1);
            check(frame.observation).equals(const ExampleObservation(1));
            check(frame.timing.deadline).isNull();
          });
    });

    test('returns null for an out-of-range index', () {
      final frames = [_frame(0, 0)];
      final container = makeContainer(
        overrides: [
          replayFramesProvider(
            gameId: 'g1',
          ).overrideWith((ref) async => frames),
          gameRulesProvider(
            gameId: 'g1',
          ).overrideWith((ref) async => const ExampleRules()),
        ],
      );

      return container
          .read(replayFramesProvider(gameId: 'g1').future)
          .then((_) => container.read(gameRulesProvider(gameId: 'g1').future))
          .then((_) {
            final frame = container.read(
              replayFrameAtProvider(gameId: 'g1', index: 9),
            );
            check(frame).isNull();
          });
    });
  });
}
