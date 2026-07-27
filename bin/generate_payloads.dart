import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:eigen_flutter/src/codegen/payload_cli.dart';
import 'package:eigen_flutter/src/codegen/payload_generator.dart';

void main(List<String> arguments) {
  final cli = PayloadGeneratorCli();
  try {
    final options = cli.parse(arguments);
    if (options == null) {
      stdout.writeln(cli.usage);
      return;
    }
    final contractFile = File(options.contract);
    final contract =
        jsonDecode(contractFile.readAsStringSync()) as Map<String, dynamic>;
    final generated = generatePayloadLibrary(contract);
    final output = File(options.output);

    if (options.check) {
      var stale = false;
      if (!output.existsSync() || output.readAsStringSync() != generated) {
        stderr.writeln(
          '${output.path} is stale; run dart run eigen_flutter:generate_payloads',
        );
        stale = true;
      }
      if (options.fixturesOutput case final fixturesOutput?) {
        final directory = Directory(fixturesOutput);
        for (final entry in contractFixtureContents(contract).entries) {
          final file = File('${directory.path}/${entry.key}');
          if (!file.existsSync() || file.readAsStringSync() != entry.value) {
            stderr.writeln('${file.path} is stale');
            stale = true;
          }
        }
      }
      if (stale) exitCode = 1;
      return;
    }

    output.parent.createSync(recursive: true);
    output.writeAsStringSync(generated);
    if (options.fixturesOutput case final fixturesOutput?) {
      writeContractFixtures(contract, Directory(fixturesOutput));
    }
    stdout.writeln('Generated ${output.path}');
  } on ArgParserException catch (error) {
    stderr
      ..writeln('generate_payloads: ${error.message}')
      ..writeln()
      ..writeln(cli.usage);
    exitCode = 64;
  } on FormatException catch (error) {
    stderr.writeln('generate_payloads: ${error.message}');
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('generate_payloads: ${error.message}');
    exitCode = 74;
  }
}
