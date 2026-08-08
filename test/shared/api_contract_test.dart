import 'package:checks/checks.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the generated client's surface to the server contract it was built
/// from.
///
/// `eigen_api` is regenerated wholesale from the server's `openapi.json`
/// (in the engine repo), so nothing in it is reviewable by diffing hand
/// edits. These checks are the drift canary: if the server changes a wire enum
/// or reshapes a payload, the regenerated package still compiles but these
/// assertions fail, which is the signal to update the call sites that dispatch
/// on the changed values.
void main() {
  group('ErrorCode', () {
    test('covers exactly the codes the server publishes', () {
      // The fallback is generated client-side rather than published on the
      // wire, so exclude it before comparing the server contract.
      final publishedCodes = ErrorCode.values.where(
        (code) => code != ErrorCode.unknownDefaultOpenApi,
      );
      check(publishedCodes.map((c) => c.value).toSet()).deepEquals({
        'notActive',
        'notReady',
        'expired',
        'notPending',
        'stateUpdated',
        'invalidPayload',
        'illegalMove',
        'unknownGame',
        'notJoinable',
        'gameFull',
        'alreadyJoined',
        'notParticipant',
        'notCreator',
        'creatorCannotLeave',
        // Raised by a route before the command reaches the game. Each exists
        // because the UI renders something specific for it.
        'schemaUnsupported',
        'usernameInvalid',
        'usernameTaken',
        'friendsOnly',
        'registrationRequired',
        'imageTooLarge',
        'unsupportedImageType',
        // Per-user write rate limiting (429).
        'rateLimited',
      });
    });

    test('does not expose the engine-internal abstain code', () {
      // `abstain` is a system-intent no-op the server converts to a 500; a
      // client must never be asked to handle it.
      check(
        ErrorCode.values.map((c) => c.value),
      ).not((v) => v.contains('abstain'));
    });
  });

  group('ErrorResponse', () {
    test('parses a coded failure into the typed enum', () {
      final parsed = ErrorResponse.fromJson({
        'error': 'Game is full',
        'code': 'gameFull',
      });

      check(parsed.error).equals('Game is full');
      check(parsed.code).equals(ErrorCode.gameFull);
    });

    test('parses an uncoded failure', () {
      // Most failures (validation, unexpected 500s) carry no code.
      final parsed = ErrorResponse.fromJson({'error': 'Invalid request'});

      check(parsed.code).isNull();
    });

    test('maps a code from a newer server to the read-side sentinel', () {
      final parsed = ErrorResponse.fromJson({
        'error': 'A newer rejection',
        'code': 'introducedLater',
      });

      check(parsed.error).equals('A newer rejection');
      check(parsed.code).equals(ErrorCode.unknownDefaultOpenApi);
      check(parsed.toJson()['code']).equals('unknown_default_open_api');
    });
  });

  group('Forward-compatible response enums', () {
    test('maps unknown game, access, and seat values to their sentinels', () {
      final parsed = GameSummary.fromJson({
        'id': 'game-1',
        'createdBy': null,
        'status': 'pausedLater',
        'access': 'tournamentLater',
        'schemaVersion': 1,
        'config': <String, dynamic>{},
        'turnSeconds': null,
        'budgetSeconds': null,
        'incrementSeconds': null,
        'rated': false,
        'ratingPool': null,
        'minPlayers': 2,
        'maxPlayers': 4,
        'shortCode': 'ABC123',
        'pendingPlayers': null,
        'turnDeadline': null,
        'outcomes': null,
        'finishedAt': null,
        'createdAt': 1,
        'updatedAt': 1,
        'participants': [
          {
            'playerIndex': 0,
            'userId': 'user-1',
            'botId': null,
            'type': 'spectatorLater',
          },
        ],
      });

      check(parsed.status).equals(GameStatus.unknownDefaultOpenApi);
      check(parsed.access).equals(GameAccess.unknownDefaultOpenApi);
      check(
        parsed.participants.single.type,
      ).equals(SeatTypeEnum.unknownDefaultOpenApi);
    });
  });

  group('RatingDelta.identity', () {
    // Flattened to a nullable pair matching `Seat`, so there is no union type
    // to destructure: exactly one of the two ids is set.
    test('carries a user identity', () {
      final identity = RatingIdentity.fromJson({
        'userId': 'user-1',
        'botId': null,
      });

      check(identity.userId).equals('user-1');
      check(identity.botId).isNull();
    });

    test('carries a bot identity', () {
      final identity = RatingIdentity.fromJson({
        'userId': null,
        'botId': 'bot-x',
      });

      check(identity.userId).isNull();
      check(identity.botId).equals('bot-x');
    });
  });
}
