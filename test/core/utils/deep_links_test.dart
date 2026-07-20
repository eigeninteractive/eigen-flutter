import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/utils/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gameInviteLink', () {
    test('builds an https /join URL for a configured host', () {
      final uri = gameInviteLink(
        'ABC123',
        appHost: 'strategy.eigeninteractive.com',
      );
      check(uri).isNotNull();
      check(uri!.scheme).equals('https');
      check(uri.host).equals('strategy.eigeninteractive.com');
      check(uri.path).equals('/join/ABC123');
    });

    test('returns null when appHost is null', () {
      check(gameInviteLink('ABC123', appHost: null)).isNull();
    });
  });

  group('legalPageUrl', () {
    test('builds an https URL on the legal host', () {
      final uri = legalPageUrl('/privacy', legalHost: 'eigeninteractive.com');
      check(uri).isNotNull();
      check(uri!.host).equals('eigeninteractive.com');
      check(uri.path).equals('/privacy');
    });

    test('returns null when legalHost is null', () {
      check(legalPageUrl('/privacy', legalHost: null)).isNull();
    });
  });
}
