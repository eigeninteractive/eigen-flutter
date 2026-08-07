import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// The tools this script drives, and how to install each.
///
/// `flutterfire` is the usual casualty, and the one worth spelling out: it is
/// not installed alongside Flutter, and `dart pub global activate` puts it in a
/// directory that is not on `PATH` by default.
const _installation = <String, String>{
  'flutterfire':
      'dart pub global activate flutterfire_cli\n'
      "  …and put Dart's global bin directory on your PATH "
      '(~/.pub-cache/bin on macOS and Linux)',
  'firebase': 'npm install -g firebase-tools',
};

const _usage = '''
Configures Firebase for this app: Android, Flutter Web, and the messaging
service worker, from one Firebase project.

Usage: dart run eigen_flutter:configure_firebase [options]

  --project <id>     The Firebase project to configure against. Omit it and
                     FlutterFire asks, which is also where a project can be
                     created. Once configured, the project already recorded in
                     firebase.json is reused.
  --account <email>  The Google account to authenticate as, for a machine
                     signed in to more than one.
  --help             Show this.

Platforms are not an option: the app is Android and Web, and the service worker
configuration this writes comes from the Web app. Run `flutterfire configure`
directly for anything this does not cover.''';

/// The options this command takes, each forwarded to `flutterfire configure`
/// with its value.
///
/// A deliberately narrow interface rather than a passthrough. This command
/// exists to configure a generated app the one way it is supported, and the
/// options that would change that — `--platforms` above all — leave the rest of
/// the script unable to finish: it needs the Web app FlutterFire records, and
/// fails several steps later if it is not there.
const _options = {'project', 'account'};

Future<void> main(List<String> rawArguments) async {
  try {
    final appRoot = Directory.current;
    // `npm run … -- --project x` strips the separator before the script sees
    // it; pnpm forwards it verbatim. Dropping it here means one documented
    // form works under either, instead of FlutterFire being handed a bare `--`
    // it has no meaning for.
    final arguments = rawArguments.where((a) => a != '--').toList();
    if (arguments.contains('--help') || arguments.contains('-h')) {
      stdout.writeln(_usage);
      return;
    }
    _rejectUnknownOptions(arguments);

    // Both tools up front. `firebase` is not needed until FlutterFire has
    // already written firebase.json and lib/firebase_options.dart, so finding
    // out then that it is missing leaves a half-configured app behind.
    await _requireExecutables(_installation.keys);

    // A re-run configures whatever the last run did, without asking again:
    // FlutterFire records the project in firebase.json, which is the same file
    // this script reads its Web app ID out of below.
    final project =
        _valueOf(arguments, 'project') ?? _configuredProject(appRoot);
    final account = _valueOf(arguments, 'account');
    final settled =
        project != null ||
        File(path.join(appRoot.path, '.firebaserc')).existsSync();
    if (!settled) {
      stdout.writeln(
        'No Firebase project chosen yet — FlutterFire will ask which to use, '
        'and can create one.\nPass --project <id> to skip that.\n',
      );
    }

    await _run('flutterfire', [
      'configure',
      // Both, always. The generated app has an android/ and a web/ and nothing
      // else, and the messaging service worker below needs the Web app.
      '--platforms=android,web',
      if (project != null) ...['--project', project],
      if (account != null) ...['--account', account],
      // `--yes` is FlutterFire's non-interactive mode, and in it a run with no
      // project aborts with FirebaseProjectRequiredException rather than
      // offering the picker. So it is passed only once the project is settled;
      // otherwise FlutterFire prompts, and stdio is inherited so it can.
      if (settled) '--yes',
    ], appRoot);

    final selectedOutput = _selectedOutput(appRoot);
    final projectId = selectedOutput?['projectId'] as String?;
    final configurations =
        selectedOutput?['configurations'] as Map<String, dynamic>?;
    final webAppId = configurations?['web'] as String?;

    if (projectId == null || webAppId == null) {
      throw const FormatException(
        'FlutterFire did not record a Web app in firebase.json. Run the '
        'command again and ensure Android and Web are configured.',
      );
    }

    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'eigen-firebase-',
    );
    try {
      final downloadedConfig = File(
        path.join(temporaryDirectory.path, 'firebase-config.json'),
      );
      await _run('firebase', [
        'apps:sdkconfig',
        'web',
        webAppId,
        '--project',
        projectId,
        '--out',
        downloadedConfig.path,
      ], appRoot);

      final config = _readJson(downloadedConfig);
      const requiredKeys = {
        'apiKey',
        'appId',
        'messagingSenderId',
        'projectId',
      };
      final missingKeys = requiredKeys
          .where(
            (key) => switch (config[key]) {
              final String value when value.isNotEmpty => false,
              _ => true,
            },
          )
          .toList();
      if (missingKeys.isNotEmpty) {
        throw FormatException(
          'Firebase returned an incomplete Web configuration: '
          '${missingKeys.join(', ')}',
        );
      }

      final output = File(path.join(appRoot.path, 'web', 'firebase-config.js'));
      output.writeAsStringSync(
        '// Generated by `dart run eigen_flutter:configure_firebase`.\n'
        '// Public Firebase app identifiers; do not edit this file by hand.\n'
        'self.firebaseConfig = Object.freeze('
        '${const JsonEncoder.withIndent('  ').convert(config)});\n',
      );
    } finally {
      temporaryDirectory.deleteSync(recursive: true);
    }

    stdout.writeln(
      'Firebase configured for Android, Flutter Web, and the messaging '
      'service worker.',
    );
  } on _UsageError catch (error) {
    stderr.writeln('configure_firebase: ${error.reason}\n\n$_usage');
    exitCode = 64;
  } on _MissingExecutables catch (error) {
    stderr.writeln(error.message);
    exitCode = 69;
  } on ProcessException catch (error) {
    // The preflight above catches this in practice. Kept for a tool that goes
    // missing between the check and its use.
    if (error.errorCode == 2) {
      stderr.writeln(_MissingExecutables([error.executable]).message);
    } else {
      stderr.writeln('configure_firebase: $error');
    }
    exitCode = 69;
  } on _CommandFailed catch (error) {
    exitCode = error.exitCode;
  } on FileSystemException catch (error) {
    stderr.writeln('configure_firebase: ${error.message}');
    exitCode = 74;
  } on FormatException catch (error) {
    stderr.writeln('configure_firebase: ${error.message}');
    exitCode = 65;
  }
}

/// The value of `--name`, in either the `--name value` or `--name=value`
/// spelling. `null` when the option is absent; a usage error when it is present
/// with nothing after it, which is otherwise silently taken as "not given".
String? _valueOf(List<String> arguments, String name) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument.startsWith('--$name=')) {
      final value = argument.substring(name.length + 3);
      if (value.isEmpty) throw _UsageError('`--$name` needs a value.');
      return value;
    }
    if (argument != '--$name') continue;
    if (index + 1 >= arguments.length) {
      throw _UsageError('`--$name` needs a value.');
    }
    return arguments[index + 1];
  }
  return null;
}

/// Fails on anything outside [_options], rather than handing it to FlutterFire
/// and letting it change what this command is for.
void _rejectUnknownOptions(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--')) continue;
    final name = argument.substring(2).split('=').first;
    if (_options.contains(name)) {
      // Skip the value, so a value that happens to look like an option is not
      // read as one.
      if (!argument.contains('=')) index++;
      continue;
    }
    throw _UsageError(
      name == 'platforms'
          ? 'This configures Android and Web, and that is not adjustable: '
                'they are the platforms the app has, and the messaging service '
                'worker is configured from the Web app.'
          : 'Unknown option `--$name`.',
    );
  }
}

/// What FlutterFire recorded in `firebase.json` for the Dart output this app
/// uses: the project it was configured against, and the app ID per platform.
/// `null` before a first run, when there is no such file.
Map<String, dynamic>? _selectedOutput(Directory appRoot) {
  final file = File(path.join(appRoot.path, 'firebase.json'));
  if (!file.existsSync()) return null;
  final platforms =
      (_readJson(file)['flutter'] as Map<String, dynamic>?)?['platforms']
          as Map<String, dynamic>?;
  final dartOutputs = platforms?['dart'] as Map<String, dynamic>?;
  return dartOutputs?['lib/firebase_options.dart'] as Map<String, dynamic>?;
}

/// The project a previous run configured. Absent, the run asks — which is what
/// it would have done anyway.
String? _configuredProject(Directory appRoot) =>
    _selectedOutput(appRoot)?['projectId'] as String?;

Map<String, dynamic> _readJson(File file) {
  final value = jsonDecode(file.readAsStringSync());
  if (value case final Map<String, dynamic> result) return result;
  throw FormatException('${file.path} must contain a JSON object.');
}

Future<void> _requireExecutables(Iterable<String> executables) async {
  final missing = <String>[];
  for (final executable in executables) {
    try {
      // The exit status is not interesting. Anything other than "no such
      // executable" means the tool is installed, and whatever is wrong with it
      // is better reported by the command that actually needs it.
      await Process.run(executable, const ['--version']);
    } on ProcessException {
      missing.add(executable);
    }
  }
  if (missing.isNotEmpty) throw _MissingExecutables(missing);
}

Future<void> _run(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final result = await process.exitCode;
  if (result != 0) throw _CommandFailed(result);
}

final class _UsageError implements Exception {
  const _UsageError(this.reason);

  final String reason;
}

final class _CommandFailed implements Exception {
  const _CommandFailed(this.exitCode);

  final int exitCode;
}

final class _MissingExecutables implements Exception {
  const _MissingExecutables(this.executables);

  final List<String> executables;

  /// Names what is missing and how to install exactly that, rather than
  /// pointing at both CLIs and leaving the reader to work out which of them
  /// they already have.
  String get message {
    final buffer =
        StringBuffer(
            'configure_firebase: could not find '
            '${executables.map((name) => '`$name`').join(' or ')}. Install '
            '${executables.length == 1 ? 'it' : 'them'} with:',
          )
          ..writeln()
          ..writeln();
    for (final name in executables) {
      buffer.writeln(
        '  ${_installation[name] ?? 'Install $name and put it on your PATH.'}',
      );
    }
    buffer
      ..writeln()
      ..write('Then run this command again.');
    return buffer.toString();
  }
}
