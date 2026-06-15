import 'package:checks/checks.dart';
import 'package:eigen_engine/features/rating/data/models/rating_change.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RatingChange round-trips through JSON', () {
    final json = <String, Object?>{
      'game_id': 'g1',
      'pool': 'rapid',
      'display_before': 100,
      'display_after': 112,
      'display_change': 12,
      'created_at': '2026-06-15T10:30:00.000Z',
    };
    check(RatingChange.fromJson(json).toJson()).deepEquals(json);
  });
}
