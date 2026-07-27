import 'package:args/args.dart';
import 'package:eigen_flutter/src/codegen/payload_cli.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses generation and check options', () {
    final options = PayloadGeneratorCli().parse([
      '--contract=game-contract.json',
      '--output',
      'lib/game/generated/payloads.dart',
      '--fixtures-output',
      'test/fixtures',
      '--check',
    ]);

    expect(options, isNotNull);
    expect(options!.contract, 'game-contract.json');
    expect(options.output, 'lib/game/generated/payloads.dart');
    expect(options.fixturesOutput, 'test/fixtures');
    expect(options.check, isTrue);
  });

  test('requires contract and output when generating', () {
    expect(
      () => PayloadGeneratorCli().parse(const []),
      throwsA(
        isA<ArgParserException>().having(
          (error) => error.message,
          'message',
          contains('contract'),
        ),
      ),
    );
  });

  test('help does not require generation options', () {
    final cli = PayloadGeneratorCli();

    expect(cli.parse(const ['--help']), isNull);
    expect(cli.parse(const ['-h']), isNull);
    expect(cli.usage, contains('--contract=<path>'));
    expect(cli.usage, contains('--output=<path>'));
    expect(cli.usage, contains('--check'));
  });

  test('rejects unknown options', () {
    expect(
      () => PayloadGeneratorCli().parse([
        '--contract',
        'game-contract.json',
        '--output',
        'payloads.dart',
        '--wat',
      ]),
      throwsA(isA<ArgParserException>()),
    );
  });
}
