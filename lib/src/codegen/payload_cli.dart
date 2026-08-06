import 'package:args/args.dart';

/// Parsed options for the payload generator executable.
final class PayloadGeneratorOptions {
  const PayloadGeneratorOptions({
    required this.contract,
    required this.output,
    required this.fixturesOutput,
    required this.check,
  });

  final String contract;
  final String output;
  final String? fixturesOutput;
  final bool check;
}

/// The command-line contract for `eigen_flutter:generate_payloads`.
final class PayloadGeneratorCli {
  PayloadGeneratorCli()
    : _parser = (ArgParser()
        ..addOption(
          'contract',
          mandatory: true,
          valueHelp: 'path',
          help: 'Input game-contract.json.',
        )
        ..addOption(
          'output',
          mandatory: true,
          valueHelp: 'path',
          help: 'Generated Dart library.',
        )
        ..addOption(
          'fixtures-output',
          valueHelp: 'directory',
          help: 'Directory for generated fixture copies.',
        )
        ..addFlag(
          'check',
          negatable: false,
          help: 'Fail instead of writing when generated files are stale.',
        )
        ..addFlag(
          'help',
          abbr: 'h',
          negatable: false,
          help: 'Show this help.',
        ));

  final ArgParser _parser;

  String get usage => '''
Generate immutable Dart payload types from an EigenInteractive game contract.

Usage:
  dart run eigen_flutter:generate_payloads [options]

Options:
${_parser.usage}''';

  /// Parses [arguments], or returns null when help was requested.
  PayloadGeneratorOptions? parse(List<String> arguments) {
    // Mandatory options should apply to generation, not to the help path.
    if (arguments.contains('--help') || arguments.contains('-h')) return null;

    final results = _parser.parse(arguments);
    return PayloadGeneratorOptions(
      contract: _requiredOption(results, 'contract'),
      output: _requiredOption(results, 'output'),
      fixturesOutput: results.option('fixtures-output'),
      check: results.flag('check'),
    );
  }

  String _requiredOption(ArgResults results, String name) {
    if (!results.wasParsed(name)) {
      throw ArgParserException('Option --$name is mandatory.', const [], name);
    }
    return results.option(name)!;
  }
}
