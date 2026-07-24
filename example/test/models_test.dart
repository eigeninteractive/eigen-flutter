/// Codec tests — the part of a game the shared fixtures cannot fully cover.
///
/// The fixtures exercise live play, because that is what the server's
/// `applyAction` produces. The *replay* observation shape has no fixture: it
/// comes from `computeObservation`'s `isReplay` branch, which no action case
/// ever reaches. So it is tested here, against a payload copied from that
/// branch of the TypeScript unit.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:rps_example/rps.dart';

void main() {
  group('RpsObservation', () {
    test('parses the live shape, where the opponent commit is absent', () {
      final obs = RpsObservation.fromJson(const {
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
      expect(obs.lastRound?.moves, [RpsMove.rock, RpsMove.scissors]);
      expect(obs.lastRound?.winner, 0);
      expect(obs.yourMove, RpsMove.paper);
      expect(obs.commits, isNull, reason: 'hidden during live play');
      expect(obs.committedBy(0), isTrue);
    });

    test('parses the replay shape, where both commits are revealed', () {
      final obs = RpsObservation.fromJson(const {
        'round': 1,
        'wins': [0, 0],
        'lastRound': null,
        'commits': ['rock', null],
      });

      expect(obs.yourMove, isNull);
      expect(obs.commits, [RpsMove.rock, null]);
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
      expect(RpsObservation.fromJson(json), RpsObservation.fromJson(json));
      expect(
        RpsObservation.fromJson(json).hashCode,
        RpsObservation.fromJson(json).hashCode,
      );
    });

    test('rejects a move the TypeScript enum cannot produce', () {
      // Closed sets, on purpose: there is no `unknownEnumValue`, so a member
      // added server-side throws here instead of rendering an empty board.
      // `checked: true` is what names the field in the message.
      expect(
        () => RpsObservation.fromJson(const {
          'round': 1,
          'wins': [0, 0],
          'lastRound': null,
          'yourMove': 'dynamite',
        }),
        throwsA(
          isA<CheckedFromJsonException>().having(
            (e) => e.key,
            'key',
            'yourMove',
          ),
        ),
      );
    });
  });

  group('RpsAction', () {
    test('round-trips through the wire shape', () {
      const action = RpsAction(move: RpsMove.scissors);
      expect(action.toJson(), {'move': 'scissors'});
      expect(RpsAction.fromJson(action.toJson()), action);
    });
  });

  test('RpsMove.beats matches the TypeScript beats() helper', () {
    expect(RpsMove.rock.beats(RpsMove.scissors), isTrue);
    expect(RpsMove.scissors.beats(RpsMove.paper), isTrue);
    expect(RpsMove.paper.beats(RpsMove.rock), isTrue);
    for (final move in RpsMove.values) {
      expect(move.beats(move), isFalse, reason: 'a matching throw draws');
    }
  });
}
