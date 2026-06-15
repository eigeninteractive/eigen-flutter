import 'package:checks/checks.dart';
import 'package:eigen_engine/features/rating/data/models/player_rating.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PlayerRating round-trips through JSON', () {
    final json = <String, Object?>{
      'pool': 'rapid',
      'mu': 25.0,
      'sigma': 8.333,
      'display_rating': 100,
    };
    check(PlayerRating.fromJson(json).toJson()).deepEquals(json);
  });
}
