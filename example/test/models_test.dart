/// Codec tests: the part of a game the shared fixtures cannot fully cover.
///
/// The fixtures exercise live play, because that is what the server's
/// `applyAction` produces. The *replay* observation shape has no fixture: it
/// comes from `computeObservation`'s `isReplay` branch, which no action case
/// ever reaches. So it is tested here, against a payload copied from that
/// branch of the TypeScript unit.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rps_example/rps.dart';

void main() {
  group('RpsV1Observation', () {
    test('parses the live shape, where the opponent commit is absent', () {
      final obs = RpsV1Observation.fromJson(const {
        'round': 2,
        'wins': [1, 0],
        'lastRound': {
          'moves': ['rock', 'scissors'],
          'winner': 0,
        },
        'yourMove': 'paper',
      });

      expect(obs.round, 2);
      expect(obs.wins, [1, 0]);
      expect(obs.lastRound?.moves, [RpsV1Move.rock, RpsV1Move.scissors]);
      expect(obs.lastRound?.winner, 0);
      expect(obs.yourMove, RpsV1Move.paper);
      expect(obs.commits, isNull, reason: 'hidden during live play');
      expect(obs.committedBy(0), isTrue);
    });

    test('parses the replay shape, where both commits are revealed', () {
      final obs = RpsV1Observation.fromJson(const {
        'round': 1,
        'wins': [0, 0],
        'lastRound': null,
        'commits': ['rock', null],
      });

      expect(obs.yourMove, isNull);
      expect(obs.commits, [RpsV1Move.rock, null]);
      expect(obs.committedBy(0), isTrue);
      expect(obs.committedBy(1), isFalse);
    });

    test('has value equality, which the fixture runner compares on', () {
      const json = {
        'round': 1,
        'wins': [0, 0],
        'lastRound': null,
        'yourMove': 'rock',
      };
      expect(RpsV1Observation.fromJson(json), RpsV1Observation.fromJson(json));
      expect(
        RpsV1Observation.fromJson(json).hashCode,
        RpsV1Observation.fromJson(json).hashCode,
      );
    });

    test('rejects a move the TypeScript enum cannot produce', () {
      expect(
        () => RpsV1Observation.fromJson(const {
          'round': 1,
          'wins': [0, 0],
          'lastRound': null,
          'yourMove': 'dynamite',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('RpsV1Observation.yourMove'),
          ),
        ),
      );
    });
  });

  group('RpsV1Action', () {
    test('round-trips through the wire shape', () {
      final action = RpsV1Action(move: RpsV1Move.scissors);
      expect(action.toJson(), {'move': 'scissors'});
      expect(RpsV1Action.fromJson(action.toJson()), action);
    });
  });

  test('RpsV1Move.beats matches the TypeScript beats() helper', () {
    expect(RpsV1Move.rock.beats(RpsV1Move.scissors), isTrue);
    expect(RpsV1Move.scissors.beats(RpsV1Move.paper), isTrue);
    expect(RpsV1Move.paper.beats(RpsV1Move.rock), isTrue);
    for (final move in RpsV1Move.values) {
      expect(move.beats(move), isFalse, reason: 'a matching throw draws');
    }
  });
}
