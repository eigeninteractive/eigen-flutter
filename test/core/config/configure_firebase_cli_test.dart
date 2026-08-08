import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

/// What `firebase login:list --json` prints when somebody is signed in, cut
/// down to the one field the preflight looks at: whether the list is empty.
const _signedIn =
    '{"status":"success","result":[{"user":{"email":"tester@example.com"}}]}';

void main() {
  test(
    'generates the service worker config for the Web app selected by FlutterFire',
    () async {
      final packageRoot = Directory.current;
      final appRoot = Directory.systemTemp.createTempSync(
        'eigen-firebase-cli-test-',
      );
      addTearDown(() => appRoot.deleteSync(recursive: true));

      Directory(path.join(appRoot.path, 'web')).createSync();
      File(path.join(appRoot.path, 'firebase.json')).writeAsStringSync(
        jsonEncode({
          'flutter': {
            'platforms': {
              'dart': {
                'lib/firebase_options.dart': {
                  'projectId': 'example-project',
                  'configurations': {'web': '1:123:web:abc'},
                },
              },
            },
          },
        }),
      );

      final fakeBin = Directory(path.join(appRoot.path, 'bin'))..createSync();
      await _writeExecutable(
        File(path.join(fakeBin.path, 'flutterfire')),
        '#!/bin/sh\nexit 0\n',
      );
      final sdkConfig = File(path.join(appRoot.path, 'sdk-config.json'))
        ..writeAsStringSync(
          jsonEncode({
            'apiKey': 'api-key',
            'appId': '1:123:web:abc',
            'messagingSenderId': '123',
            'projectId': 'example-project',
            'authDomain': 'example-project.firebaseapp.com',
          }),
        );
      await _writeExecutable(
        File(path.join(fakeBin.path, 'firebase')),
        '''#!/bin/sh
if [ "\$1" = "login:list" ]; then
  printf '%s\\n' '$_signedIn'
  exit 0
fi
output=""
previous=""
for argument in "\$@"; do
  if [ "\$previous" = "--out" ]; then output="\$argument"; fi
  previous="\$argument"
done
cp "\$EIGEN_TEST_FIREBASE_CONFIG" "\$output"
echo "App configuration is written in \$output"
''',
      );

      final result = await Process.run(
        'dart',
        [path.join(packageRoot.path, 'bin', 'configure_firebase.dart')],
        workingDirectory: appRoot.path,
        environment: {
          ...Platform.environment,
          'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
          'EIGEN_TEST_FIREBASE_CONFIG': sdkConfig.path,
        },
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final generated = File(
        path.join(appRoot.path, 'web', 'firebase-config.js'),
      ).readAsStringSync();
      expect(generated, contains('self.firebaseConfig = Object.freeze('));
      expect(generated, contains('"appId": "1:123:web:abc"'));
      expect(generated, contains('"projectId": "example-project"'));
      expect(generated, isNot(contains('REPLACE_ME')));
      // The download is an intermediate: read, checked, rewritten as the
      // service worker's config, and deleted. Announcing the temporary file it
      // landed in points the reader at a path that no longer exists.
      expect(result.stdout, isNot(contains('App configuration is written in')));
      expect(
        result.stdout,
        contains('Firebase configured for Android, Flutter Web'),
      );
      // Which project and which apps, because FlutterFire reuses an app the
      // project already had without saying so; the two runs are otherwise
      // indistinguishable.
      expect(result.stdout, contains('project  example-project'));
      expect(result.stdout, contains('web      1:123:web:abc'));
    },
    skip: Platform.isWindows,
  );

  group('before it starts', () {
    /// The script's own exit and stderr against a `firebase` that answers
    /// `login:list` with [accounts] and does nothing else.
    Future<ProcessResult> run(String accounts) async {
      final packageRoot = Directory.current;
      final appRoot = Directory.systemTemp.createTempSync(
        'eigen-firebase-login-',
      );
      addTearDown(() => appRoot.deleteSync(recursive: true));
      final fakeBin = Directory(path.join(appRoot.path, 'bin'))..createSync();
      await _writeExecutable(
        File(path.join(fakeBin.path, 'flutterfire')),
        '#!/bin/sh\nexit 0\n',
      );
      await _writeExecutable(
        File(path.join(fakeBin.path, 'firebase')),
        '#!/bin/sh\nprintf \'%s\\n\' \'$accounts\'\nexit 0\n',
      );

      return Process.run(
        'dart',
        [path.join(packageRoot.path, 'bin', 'configure_firebase.dart')],
        workingDirectory: appRoot.path,
        environment: {
          ...Platform.environment,
          'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
        },
      );
    }

    test('says which command signs in, rather than letting FlutterFire '
        'fail on it', () async {
      final result = await run('{"status":"success","result":[]}');

      expect(result.exitCode, 77, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, contains('firebase login'));
    });

    test('leaves an answer it does not understand to the tools that '
        'authenticate', () async {
      // Fails open. A `firebase` whose output grows a different shape must not
      // block a machine that is perfectly well signed in; the commands below
      // are the ones that actually need the credentials.
      final result = await run('not json at all');

      expect(result.exitCode, isNot(77));
      expect(result.stderr, isNot(contains('firebase login')));
    });
  }, skip: Platform.isWindows);

  group('the arguments handed to FlutterFire', () {
    /// Runs the script against a `flutterfire` that records its arguments and
    /// stops there, and returns what it was called with. `firebase.json` is
    /// never written, so the script fails straight after, which is not what is
    /// under test here.
    Future<List<String>> flutterFireArguments(
      List<String> arguments, {
      bool firebaserc = false,
      bool configured = false,
    }) async {
      final packageRoot = Directory.current;
      final appRoot = Directory.systemTemp.createTempSync(
        'eigen-firebase-args-',
      );
      addTearDown(() => appRoot.deleteSync(recursive: true));
      if (firebaserc) {
        File(path.join(appRoot.path, '.firebaserc')).writeAsStringSync(
          jsonEncode({
            'projects': {'default': 'example-project'},
          }),
        );
      }
      if (configured) {
        File(path.join(appRoot.path, 'firebase.json')).writeAsStringSync(
          jsonEncode({
            'flutter': {
              'platforms': {
                'dart': {
                  'lib/firebase_options.dart': {
                    'projectId': 'example-project',
                    'configurations': {'web': '1:123:web:abc'},
                  },
                },
              },
            },
          }),
        );
      }

      final recorded = File(path.join(appRoot.path, 'argv'));
      final fakeBin = Directory(path.join(appRoot.path, 'bin'))..createSync();
      await _writeExecutable(
        File(path.join(fakeBin.path, 'flutterfire')),
        '#!/bin/sh\nprintf "%s\\n" "\$@" > "${recorded.path}"\nexit 0\n',
      );
      await _writeExecutable(
        File(path.join(fakeBin.path, 'firebase')),
        '#!/bin/sh\nexit 0\n',
      );

      await Process.run(
        'dart',
        [
          path.join(packageRoot.path, 'bin', 'configure_firebase.dart'),
          ...arguments,
        ],
        workingDirectory: appRoot.path,
        environment: {
          ...Platform.environment,
          'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
        },
      );

      return recorded.readAsLinesSync();
    }

    test('asks rather than failing when no project has been chosen', () async {
      // `--yes` is FlutterFire's non-interactive mode, and in it a run with no
      // project aborts with FirebaseProjectRequiredException instead of
      // offering the picker. A first run has no project yet, so it must prompt.
      final argv = await flutterFireArguments(const []);

      expect(argv, contains('configure'));
      expect(argv, contains('--platforms=android,web'));
      expect(argv, isNot(contains('--yes')));
    });

    test('skips the prompts once the project is settled', () async {
      expect(
        await flutterFireArguments(const ['--project', 'example-project']),
        containsAll(['--yes', '--project', 'example-project']),
      );
      // `firebase use` records the default project here, and FlutterFire reads
      // it, so this run has nothing left to ask about either.
      expect(
        await flutterFireArguments(const [], firebaserc: true),
        contains('--yes'),
      );
    });

    test('ignores the separator pnpm forwards but npm swallows', () async {
      // So one documented form, `run firebase:configure -- --project x`,
      // works under either, rather than FlutterFire being handed a bare `--`
      // that means nothing to it.
      final argv = await flutterFireArguments(const [
        '--',
        '--project',
        'example-project',
      ]);

      expect(argv, isNot(contains('--')));
      expect(argv, containsAll(['--yes', '--project', 'example-project']));
    });

    test('reuses the project a previous run recorded', () async {
      // FlutterFire writes the project into firebase.json, which this script
      // already reads its Web app ID out of, so re-running to pick up a new
      // configuration does not ask the same question again.
      final argv = await flutterFireArguments(const [], configured: true);

      expect(argv, containsAll(['--yes', '--project', 'example-project']));
    });
  }, skip: Platform.isWindows);

  group('options it does not take', () {
    /// The script's own exit and stderr, with both tools present so nothing
    /// else can be what failed.
    Future<ProcessResult> run(List<String> arguments) async {
      final packageRoot = Directory.current;
      final appRoot = Directory.systemTemp.createTempSync(
        'eigen-firebase-use-',
      );
      addTearDown(() => appRoot.deleteSync(recursive: true));
      final fakeBin = Directory(path.join(appRoot.path, 'bin'))..createSync();
      for (final tool in ['flutterfire', 'firebase']) {
        await _writeExecutable(
          File(path.join(fakeBin.path, tool)),
          '#!/bin/sh\nexit 0\n',
        );
      }

      return Process.run(
        'dart',
        [
          path.join(packageRoot.path, 'bin', 'configure_firebase.dart'),
          ...arguments,
        ],
        workingDirectory: appRoot.path,
        environment: {
          ...Platform.environment,
          'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
        },
      );
    }

    test('refuses to configure other platforms, and says why', () async {
      // Not a passthrough: the app has an android/ and a web/, and the service
      // worker configuration is derived from the Web app. Accepting this would
      // fail several steps later, at "did not record a Web app".
      final result = await run(const ['--platforms=ios']);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('Android and Web'));
      expect(result.stderr, contains('--project <id>'));
    });

    test(
      'names an option it does not know rather than passing it on',
      () async {
        final result = await run(const ['--ios-bundle-id', 'com.example']);

        expect(result.exitCode, 64);
        expect(result.stderr, contains('Unknown option `--ios-bundle-id`'));
      },
    );

    test('rejects an option given without its value', () async {
      final result = await run(const ['--project']);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('`--project` needs a value'));
    });

    test('prints the usage on request', () async {
      final result = await run(const ['--help']);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('--project <id>'));
      expect(result.stdout, contains('--account <email>'));
    });
  }, skip: Platform.isWindows);

  test('shows what the quiet command said when it fails', () async {
    // Captured is not swallowed. The download runs with its output held back
    // because it has nothing to say on success; a failure is the other case.
    final packageRoot = Directory.current;
    final appRoot = Directory.systemTemp.createTempSync('eigen-firebase-fail-');
    addTearDown(() => appRoot.deleteSync(recursive: true));

    Directory(path.join(appRoot.path, 'web')).createSync();
    File(path.join(appRoot.path, 'firebase.json')).writeAsStringSync(
      jsonEncode({
        'flutter': {
          'platforms': {
            'dart': {
              'lib/firebase_options.dart': {
                'projectId': 'example-project',
                'configurations': {'web': '1:123:web:abc'},
              },
            },
          },
        },
      }),
    );

    final fakeBin = Directory(path.join(appRoot.path, 'bin'))..createSync();
    await _writeExecutable(
      File(path.join(fakeBin.path, 'flutterfire')),
      '#!/bin/sh\nexit 0\n',
    );
    await _writeExecutable(
      File(path.join(fakeBin.path, 'firebase')),
      '''#!/bin/sh
if [ "\$1" = "login:list" ]; then
  printf '%s\\n' '$_signedIn'
  exit 0
fi
echo "Error: Failed to get Firebase project example-project" >&2
exit 3
''',
    );

    final result = await Process.run(
      'dart',
      [path.join(packageRoot.path, 'bin', 'configure_firebase.dart')],
      workingDirectory: appRoot.path,
      environment: {
        ...Platform.environment,
        'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
      },
    );

    expect(result.exitCode, 3);
    expect(result.stderr, contains('Failed to get Firebase project'));
    expect(
      File(path.join(appRoot.path, 'web', 'firebase-config.js')).existsSync(),
      isFalse,
    );
  }, skip: Platform.isWindows);

  test('names the missing tool and how to install it', () async {
    final packageRoot = Directory.current;
    final appRoot = Directory.systemTemp.createTempSync(
      'eigen-firebase-missing-',
    );
    addTearDown(() => appRoot.deleteSync(recursive: true));

    // `firebase` present, `flutterfire` absent: the common case, because
    // FlutterFire is not installed alongside Flutter and lands somewhere that
    // is not on PATH. `dart` itself has to stay findable to run the script.
    final fakeBin = Directory(path.join(appRoot.path, 'bin'))..createSync();
    await _writeExecutable(
      File(path.join(fakeBin.path, 'firebase')),
      '#!/bin/sh\nexit 0\n',
    );

    // Located rather than assumed: under `flutter test` the running executable
    // is flutter_tester, so its directory is not where `dart` lives.
    final dart = ((await Process.run('which', ['dart'])).stdout as String)
        .trim();
    expect(dart, isNotEmpty, reason: 'dart must be on PATH to run this test');

    final result = await Process.run(
      'dart',
      [path.join(packageRoot.path, 'bin', 'configure_firebase.dart')],
      workingDirectory: appRoot.path,
      environment: {
        ...Platform.environment,
        // Trimmed to hide whatever is installed on this machine, but not so
        // far that `dart` breaks: it is a shell wrapper that resolves `bash`
        // through PATH.
        'PATH': '${fakeBin.path}:${path.dirname(dart)}:/usr/bin:/bin',
      },
    );

    expect(result.exitCode, 69, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('could not find `flutterfire`'));
    expect(result.stderr, contains('dart pub global activate flutterfire_cli'));
    // The tool it did find has no business in the message.
    expect(result.stderr, isNot(contains('firebase-tools')));
  }, skip: Platform.isWindows);
}

Future<void> _writeExecutable(File file, String contents) async {
  file.writeAsStringSync(contents);
  final result = await Process.run('chmod', ['+x', file.path]);
  if (result.exitCode != 0) {
    throw ProcessException('chmod', ['+x', file.path], '${result.stderr}');
  }
}
