import 'package:checks/checks.dart';
import 'package:eigen_engine/features/profile/data/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UserProfile round-trips through JSON', () {
    final json = <String, Object?>{
      'id': 'u1',
      'username': 'alice',
      'email': 'alice@example.com',
      'payment_tier': 'free',
      'display_name': 'Alice',
      'avatar_url': null,
      'created_at': '2026-06-15T10:30:00.000Z',
      'updated_at': '2026-06-15T10:31:00.000Z',
    };
    check(UserProfile.fromJson(json).toJson()).deepEquals(json);
  });
}
