import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/review/review_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/container.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('onWin increments the count and persists it', () async {
    SharedPreferences.setMockInitialValues({});
    final container = makeContainer();
    await container.read(reviewProvider.future);

    await container.read(reviewProvider.notifier).onWin();

    check(container.read(reviewProvider).value).equals(1);

    final reopened = makeContainer();
    check(await reopened.read(reviewProvider.future)).equals(1);
  });

  test(
    'crossing a multiple of 5 still completes (review path no-ops in test)',
    () async {
      SharedPreferences.setMockInitialValues({'total_wins': 4});
      final container = makeContainer();
      await container.read(reviewProvider.future);

      await container.read(reviewProvider.notifier).onWin();

      check(container.read(reviewProvider).value).equals(5);
    },
  );
}
