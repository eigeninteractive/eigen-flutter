import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_flutter/core/utils/package_info_provider.dart';
import 'package:eigen_flutter/features/about/presentation/screens/about_screen.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';

import '../../helpers/fakes.dart';

/// Sample module that supplies rules content for the About page.
class _RulesModule extends SampleModule {
  const _RulesModule();

  @override
  Widget buildRules(BuildContext context) => const Text('THE RULES');
}

void main() {
  const config = AppConfig(
    branding: Branding(
      appName: 'Test App',
      seedColor: Colors.indigo,
      madeByCredit: 'Made by tester',
    ),
    engine: EngineConfig(
      apiBaseUrl: 'https://example.test',
      googleWebClientId: 'client',
      firebaseVapidKey: 'test-vapid-key',
    ),
  );

  Future<void> pumpAbout(WidgetTester tester, GameModule module) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          currentGameModuleProvider.overrideWithValue(module),
          packageInfoProvider.overrideWith(
            (ref) async => PackageInfo(
              appName: 'Test App',
              packageName: 'com.example.test',
              version: '1.2.3',
              buildNumber: '42',
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AboutScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders app name, version, credit and game rules', (
    tester,
  ) async {
    await pumpAbout(tester, const _RulesModule());

    expect(find.text('Test App'), findsOneWidget);
    expect(find.text('THE RULES'), findsOneWidget);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('Made by tester'), findsOneWidget);
  });

  testWidgets('renders the rules content supplied by the module', (
    tester,
  ) async {
    await pumpAbout(tester, const SampleModule());

    expect(find.text('Sample rules'), findsOneWidget);
  });
}
