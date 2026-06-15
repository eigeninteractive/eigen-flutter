import 'package:checks/checks.dart';
import 'package:eigen_engine/features/social/data/models/friendship.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Friendship round-trips with a RelationshipStatus enum', () {
    final json = <String, Object?>{
      'user_id': 'u1',
      'friend_id': 'u2',
      'status': 'accepted',
      'initiated_by': 'u1',
      'created_at': '2026-06-15T10:30:00.000Z',
      'updated_at': '2026-06-15T10:31:00.000Z',
    };
    check(Friendship.fromJson(json).toJson()).deepEquals(json);
  });

  test('decodes each RelationshipStatus value', () {
    for (final name in const ['pending', 'accepted', 'blocked']) {
      final friendship = Friendship.fromJson(<String, Object?>{
        'user_id': 'u1',
        'friend_id': 'u2',
        'status': name,
        'initiated_by': 'u1',
        'created_at': '2026-06-15T10:30:00.000Z',
        'updated_at': '2026-06-15T10:30:00.000Z',
      });
      check(friendship.status.name).equals(name);
    }
  });
}
