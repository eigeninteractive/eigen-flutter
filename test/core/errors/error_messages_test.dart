import 'package:checks/checks.dart';
import 'package:eigen_engine/core/errors/error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('humanize', () {
    test('maps known server messages to friendly copy', () {
      check(humanize(Exception('Not your turn'))).equals("It's not your turn.");
      check(
        humanize(Exception('Game is full')),
      ).equals('This game is already full.');
      check(
        humanize(Exception('Username already taken')),
      ).equals('That username is already taken.');
    });

    test('maps network errors', () {
      check(
        humanize(Exception('SocketException: failed host lookup')),
      ).equals("Can't reach the server. Check your connection.");
    });

    test('falls back for unrecognised errors', () {
      check(
        humanize(Exception('totally unexpected')),
      ).equals('Something went wrong. Please try again.');
    });
  });
}
