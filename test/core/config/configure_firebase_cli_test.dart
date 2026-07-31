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
}

Future<void> _writeExecutable(File file, String contents) async {
  file.writeAsStringSync(contents);
  final result = await Process.run('chmod', ['+x', file.path]);
  if (result.exitCode != 0) {
    throw ProcessException('chmod', ['+x', file.path], '${result.stderr}');
  }
}
