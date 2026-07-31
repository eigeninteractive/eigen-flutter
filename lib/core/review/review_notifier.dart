import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_flutter/core/storage/shared_preferences_provider.dart';

part 'review_notifier.g.dart';

/// Tracks total wins and gates in-app review prompts.
///
/// State is the lifetime win count, persisted across sessions via
/// [SharedPreferences]. A review prompt is requested every [_reviewEveryNWins]
/// wins, regardless of whether the game was rated. The OS enforces its own
/// quota (3× per year on both platforms) and silently no-ops when it is hit.
@Riverpod(keepAlive: true)
class ReviewNotifier extends _$ReviewNotifier {
  static const _key = 'total_wins';
  static const _reviewEveryNWins = 5;

  @override
  Future<int> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    return prefs.getInt(_key) ?? 0;
  }

  /// Records a win. Requests a review when the total is a multiple of
  /// [_reviewEveryNWins].
  Future<void> onWin() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final count = (state.value ?? 0) + 1;
    await prefs.setInt(_key, count);
    state = AsyncData(count);

    if (count % _reviewEveryNWins == 0) {
      await _maybeRequestReview();
    }
  }

  Future<void> _maybeRequestReview() async {
    // Browser stores do not expose the native in-app review API.
    if (kIsWeb) return;
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    } catch (e, stack) {
      developer.log(
        'In-app review request failed',
        name: 'app.review',
        error: e,
        stackTrace: stack,
      );
    }
  }
}
