import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

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
output=""
previous=""
for argument in "\$@"; do
  if [ "\$previous" = "--out" ]; then output="\$argument"; fi
  previous="\$argument"
done
cp "\$EIGEN_TEST_FIREBASE_CONFIG" "\$output"
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
    },
    skip: Platform.isWindows,
  );

  test('names the missing tool and how to install it', () async {
    final packageRoot = Directory.current;
    final appRoot = Directory.systemTemp.createTempSync(
      'eigen-firebase-missing-',
    );
    addTearDown(() => appRoot.deleteSync(recursive: true));

    // `firebase` present, `flutterfire` absent — the common case, because
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
