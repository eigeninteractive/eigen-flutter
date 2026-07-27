import 'dart:io';

import 'package:eigen_flutter/src/codegen/payload_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const objectSchema = <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'value': <String, dynamic>{'type': 'integer'},
    },
    'required': <String>['value'],
  };

  Map<String, dynamic> contract() => <String, dynamic>{
    'formatVersion': 1,
    'game': 'Counter',
    'versions': <String, dynamic>{
      '2': <String, dynamic>{
        'schemas': <String, dynamic>{
          'observation': objectSchema,
          'action': objectSchema,
          'config': objectSchema,
          'state': objectSchema,
        },
      },
      '1': <String, dynamic>{
        'schemas': <String, dynamic>{
          'observation': objectSchema,
          'action': objectSchema,
          'config': objectSchema,
          'state': objectSchema,
        },
      },
    },
    'fixtures': <dynamic>[],
  };

  test('generates stable names and rules bases for every version', () {
    final source = generatePayloadLibrary(contract());

    expect(source, contains('final class CounterV1Observation'));
    expect(source, contains('final class CounterV2Observation'));
    expect(source, contains('abstract class CounterV1RulesBase'));
    expect(source, contains('abstract class CounterV2RulesBase'));
    expect(
      source,
      contains(
        'extends GameRules<CounterV1Observation, CounterV1Action, CounterV1Config>',
      ),
    );
    expect(source, isNot(contains('GamePayloadCodec')));
    expect(
      source.indexOf('CounterV1Observation'),
      lessThan(source.indexOf('CounterV2Observation')),
    );
  });

  test('derives Dart type names from the contract game name', () {
    final exampleSource = generatePayloadLibrary(
      contract()..['game'] = 'Example Game',
    );
    expect(exampleSource, contains('final class ExampleGameV1Observation'));
    expect(exampleSource, contains('abstract class ExampleGameV1RulesBase'));

    final numericSource = generatePayloadLibrary(contract()..['game'] = '2048');
    expect(numericSource, contains('final class Game2048V1Observation'));
  });

  test('escapes unusual wire names and enum values as Dart literals', () {
    final unusualSchema = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        r"quote'$key": <String, dynamic>{
          'type': 'string',
          'enum': <String>[r"ready'$now"],
        },
      },
      'required': <String>[r"quote'$key"],
    };
    final value = contract();
    final schemas =
        ((value['versions'] as Map<String, dynamic>)['1']
                as Map<String, dynamic>)['schemas']
            as Map<String, dynamic>;
    schemas['action'] = unusualSchema;

    final source = generatePayloadLibrary(value);

    expect(source, contains(r'\$key'));
    expect(source, contains(r'\$now'));
    expect(source, contains('enum CounterV1ActionQuoteKey'));
  });

  test('rejects wire members that normalize to the same Dart identifier', () {
    final collidingSchema = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'display-name': <String, dynamic>{'type': 'string'},
        'display_name': <String, dynamic>{'type': 'string'},
      },
    };
    final value = contract();
    final schemas =
        ((value['versions'] as Map<String, dynamic>)['1']
                as Map<String, dynamic>)['schemas']
            as Map<String, dynamic>;
    schemas['action'] = collidingSchema;

    expect(() => generatePayloadLibrary(value), throwsFormatException);
  });

  test('rejects unsupported contract versions', () {
    expect(
      () => generatePayloadLibrary(<String, dynamic>{
        ...contract(),
        'formatVersion': 99,
      }),
      throwsFormatException,
    );
  });

  test('copies fixtures without permitting path traversal', () {
    final directory = Directory.systemTemp.createTempSync('eigen-fixtures-');
    addTearDown(() => directory.deleteSync(recursive: true));

    final value = contract()
      ..['fixtures'] = <dynamic>[
        <String, dynamic>{
          'path': 'v1/case.json',
          'document': <String, dynamic>{'schemaVersion': 1},
        },
      ];
    writeContractFixtures(value, directory);
    expect(
      File('${directory.path}/v1/case.json').readAsStringSync(),
      contains('"schemaVersion": 1'),
    );

    value['fixtures'] = <dynamic>[
      <String, dynamic>{
        'path': '../escape.json',
        'document': <String, dynamic>{},
      },
    ];
    expect(
      () => writeContractFixtures(value, directory),
      throwsFormatException,
    );
  });
}
