import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/theme/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/container.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to ThemeMode.system when nothing is persisted', () async {
    final container = makeContainer();
    check(
      await container.read(themeControllerProvider.future),
    ).equals(ThemeMode.system);
  });

  test('setTheme updates state and persists across containers', () async {
    final container = makeContainer();
    await container.read(themeControllerProvider.future);
    await container
        .read(themeControllerProvider.notifier)
        .setTheme(ThemeMode.dark);

    check(container.read(themeControllerProvider).value).equals(ThemeMode.dark);

    // A fresh container rebuilds from SharedPreferences and sees the value.
    final reopened = makeContainer();
    check(
      await reopened.read(themeControllerProvider.future),
    ).equals(ThemeMode.dark);
  });
}
