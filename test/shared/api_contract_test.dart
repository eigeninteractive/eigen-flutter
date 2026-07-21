import 'package:checks/checks.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the generated client's surface to the server contract it was built
/// from.
///
/// `eigen_api` is regenerated wholesale from the server's `openapi.json`
/// (`tool/generate_api.sh`), so nothing in it is reviewable by diffing hand
/// edits. These checks are the drift canary: if the server changes a wire enum
/// or reshapes a payload, the regenerated package still compiles but these
/// assertions fail, which is the signal to update the call sites that dispatch
/// on the changed values.
void main() {
  group('ErrorCode', () {
    test('covers exactly the codes the server publishes', () {
      // Adding a member server-side is a wire change that needs a
      // schema-version bump; this list is the client half of that contract.
      check(ErrorCode.values.map((c) => c.value).toSet()).deepEquals({
        'not_active',
        'not_ready',
        'expired',
        'not_pending',
        'state_updated',
        'invalid_payload',
        'illegal_move',
        'unknown_game',
        'not_joinable',
        'game_full',
        'already_joined',
        'not_participant',
        'not_creator',
        'creator_cannot_leave',
        // Raised by a route before the command reaches the game. Each exists
        // because the UI renders something specific for it.
        'schema_unsupported',
        'username_invalid',
        'username_taken',
        'friends_only',
        'registration_required',
        'image_too_large',
        'unsupported_image_type',
      });
    });

    test('does not expose the engine-internal abstain code', () {
      // `abstain` is a system-intent no-op the server converts to a 500; a
      // client must never be asked to handle it.
      check(ErrorCode.values.map((c) => c.value)).not((v) => v.contains('abstain'));
    });
  });

  group('ErrorResponse', () {
    test('parses a coded failure into the typed enum', () {
      final parsed = ErrorResponse.fromJson({
        'error': 'Game is full',
        'code': 'game_full',
      });

      check(parsed.error).equals('Game is full');
      check(parsed.code).equals(ErrorCode.gameFull);
    });

    test('parses an uncoded failure', () {
      // Most failures (validation, unexpected 500s) carry no code.
      final parsed = ErrorResponse.fromJson({'error': 'Invalid request'});

      check(parsed.code).isNull();
    });
  });

  group('RatingDelta.identity', () {
    // Flattened to a nullable pair matching `Seat`, so there is no union type
    // to destructure — exactly one of the two ids is set.
    test('carries a user identity', () {
      final identity = RatingIdentity.fromJson({
        'user_id': 'user-1',
        'bot_id': null,
      });

      check(identity.userId).equals('user-1');
      check(identity.botId).isNull();
    });

    test('carries a bot identity', () {
      final identity = RatingIdentity.fromJson({
        'user_id': null,
        'bot_id': 'bot-x',
      });

      check(identity.userId).isNull();
      check(identity.botId).equals('bot-x');
    });
  });
}
