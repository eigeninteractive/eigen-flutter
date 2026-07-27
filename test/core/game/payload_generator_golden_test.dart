import 'dart:convert';
import 'dart:io';

import 'package:eigen_flutter/src/codegen/payload_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/codegen/kitchen_sink_payloads.dart';

void main() {
  const contractPath = 'test/fixtures/codegen/kitchen_sink_contract.json';
  const payloadsPath = 'test/fixtures/codegen/kitchen_sink_payloads.dart';

  test('the broad generated payload fixture has no drift', () {
    final contract =
        jsonDecode(File(contractPath).readAsStringSync())
            as Map<String, dynamic>;

    expect(
      generatePayloadLibrary(contract),
      File(payloadsPath).readAsStringSync(),
    );
  });

  test('generated v1 payloads decode and encode every supported shape', () {
    final wire = <String, dynamic>{
      'profile': <String, dynamic>{'display-name': 'Ada', 'nickname': null},
      'history': <dynamic>[
        <String, dynamic>{'display-name': 'Grace', 'nickname': 'Amazing Grace'},
      ],
      'matrix': <dynamic>[2, 4],
      'possible-moves': <dynamic>['class', null, r'cost$money'],
      r"quote'$key": r'literal$value',
    };

    final observation = Game2048ArenaV1Observation.fromJson(wire);

    expect(observation.profile.displayName, 'Ada');
    expect(observation.profile.nickname, isNull);
    expect(observation.history!.single.nickname, 'Amazing Grace');
    expect(observation.matrix, <int>[2, 4]);
    expect(observation.possibleMoves, <Game2048ArenaV1Move?>[
      Game2048ArenaV1Move.classValue,
      null,
      Game2048ArenaV1Move.costMoney,
    ]);
    expect(observation.note, isNull);
    expect(observation.quoteKey, r'literal$value');
    expect(observation.toJson(), wire);
    expect(Game2048ArenaV1Observation.fromJson(wire), observation);
    expect(
      Game2048ArenaV1Observation.fromJson(wire).hashCode,
      observation.hashCode,
    );
    expect(() => observation.matrix.add(8), throwsUnsupportedError);
    expect(() => observation.history!.clear(), throwsUnsupportedError);
  });

  test('generated nested actions and configs round-trip', () {
    final actionWire = <String, dynamic>{
      'move': 'in-progress',
      'targets': <dynamic>[1, 3],
      'metadata': <String, dynamic>{'switch': true},
    };
    final action = Game2048ArenaV1Action.fromJson(actionWire);

    expect(action.move, Game2048ArenaV1Move.inProgress);
    expect(action.metadata!.switchValue, isTrue);
    expect(action.toJson(), actionWire);
    expect(() => action.targets.add(5), throwsUnsupportedError);

    final configWire = <String, dynamic>{
      'mode': 'team-play',
      'level': 2,
      'labels': <dynamic>['ranked', null],
    };
    final config = Game2048ArenaV1Config.fromJson(configWire);

    expect(config.mode, Game2048ArenaV1ConfigMode.teamPlay);
    expect(config.labels, <String?>['ranked', null]);
    expect(config.toJson(), configWire);
    expect(() => config.labels.add('new'), throwsUnsupportedError);
  });

  test('generated v2 types are distinct and use normalized wire names', () {
    expect(
      Game2048ArenaV2Observation.fromJson(<String, dynamic>{
        'turn': 7,
      }).toJson(),
      <String, dynamic>{'turn': 7},
    );
    expect(
      Game2048ArenaV2Action.fromJson(<String, dynamic>{'pass': true}).toJson(),
      <String, dynamic>{'pass': true},
    );
    expect(
      Game2048ArenaV2Config.fromJson(<String, dynamic>{
        'board-size': 4,
      }).boardSize,
      4,
    );
  });

  test('required nullable fields distinguish absence from explicit null', () {
    expect(
      () => Game2048ArenaV1Profile.fromJson(<String, dynamic>{
        'display-name': 'Ada',
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains(
            'Game2048ArenaV1Profile.nickname: required field is missing',
          ),
        ),
      ),
    );
    expect(
      Game2048ArenaV1Profile.fromJson(<String, dynamic>{
        'display-name': 'Ada',
        'nickname': null,
      }).nickname,
      isNull,
    );
  });

  test('decode errors retain the nested collection path', () {
    expect(
      () => Game2048ArenaV1Observation.fromJson(<String, dynamic>{
        'profile': <String, dynamic>{'display-name': 'Ada', 'nickname': null},
        'matrix': <dynamic>[2, 'four'],
        'possible-moves': <dynamic>[],
        r"quote'$key": 'value',
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Game2048ArenaV1Observation.matrix[1]: expected an integer'),
        ),
      ),
    );
  });

  test('game payload enums remain strict within a schema version', () {
    expect(
      () => Game2048ArenaV1Move.fromJson('future-move'),
      throwsFormatException,
    );
  });
}
