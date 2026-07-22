import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/api/avatar_url.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = 'https://api.example.com';

void main() {
  test('resolves the relative worker route', () {
    // The zoneless default: no public bucket base configured.
    check(
      resolveAvatarUrl('/avatars/u1?v=123', _base),
    ).equals('https://api.example.com/avatars/u1?v=123');
  });

  test('passes an absolute bucket URL through untouched', () {
    // What a custom domain or r2.dev deployment stores.
    check(
      resolveAvatarUrl('https://cdn.example.com/u1?v=123', _base),
    ).equals('https://cdn.example.com/u1?v=123');
  });

  test('preserves the cache-buster', () {
    // Losing ?v= would serve the previous avatar until a cache expired.
    check(
      resolveAvatarUrl('/avatars/u1?v=999', _base),
    ).isNotNull().endsWith('?v=999');
  });

  test('tolerates a base with a trailing slash', () {
    check(
      resolveAvatarUrl('/avatars/u1?v=1', 'https://api.example.com/'),
    ).equals('https://api.example.com/avatars/u1?v=1');
  });

  test('is null for a user with no avatar', () {
    check(resolveAvatarUrl(null, _base)).isNull();
    check(resolveAvatarUrl('', _base)).isNull();
  });
}
