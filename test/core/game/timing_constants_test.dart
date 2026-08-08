import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/game/timing_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('softDeadlineMarginFor', () {
    test('returns the full margin for a comfortably long window', () {
      // 10s window: 25% cap (2.5s) exceeds the 1s target, so target wins.
      check(
        softDeadlineMarginFor(const Duration(seconds: 10)),
      ).equals(kSoftDeadlineMargin);
    });

    test('caps the margin to a fraction of a short window', () {
      // 2s window: 25% cap (0.5s) is below the 1s target, so the cap wins,
      // a short Nope/hook-override window is not swallowed.
      check(
        softDeadlineMarginFor(const Duration(seconds: 2)),
      ).equals(const Duration(milliseconds: 500));
    });

    test('returns zero for a non-positive window', () {
      check(softDeadlineMarginFor(Duration.zero)).equals(Duration.zero);
      check(
        softDeadlineMarginFor(const Duration(seconds: -5)),
      ).equals(Duration.zero);
    });

    test('never exceeds 25% of the window', () {
      for (final ms in [100, 800, 1500, 3200, 9000]) {
        final window = Duration(milliseconds: ms);
        final margin = softDeadlineMarginFor(window);
        check(margin.inMicroseconds)
          ..isLessOrEqual((window.inMicroseconds * 0.25).round())
          ..isGreaterOrEqual(0);
      }
    });
  });
}
