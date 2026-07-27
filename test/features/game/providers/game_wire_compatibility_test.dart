import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Seat seat(SeatTypeEnum type) =>
      Seat(playerIndex: 0, userId: 'user', botId: null, type: type);

  test('known gameplay enums remain compatible', () {
    final compatibility = evaluateGameWireCompatibility(
      summaryStatus: GameStatus.active,
      summarySeats: [seat(SeatTypeEnum.human)],
    );

    expect(compatibility.requiresUpdate, isFalse);
  });

  test('unknown game status requires an update', () {
    final compatibility = evaluateGameWireCompatibility(
      summaryStatus: GameStatus.unknownDefaultOpenApi,
    );

    expect(compatibility.unknownStatus, isTrue);
    expect(compatibility.requiresUpdate, isTrue);
  });

  test('unknown seat type requires an update', () {
    final compatibility = evaluateGameWireCompatibility(
      rosterStatus: GameStatus.waiting,
      rosterSeats: [seat(SeatTypeEnum.unknownDefaultOpenApi)],
    );

    expect(compatibility.unknownSeatType, isTrue);
    expect(compatibility.requiresUpdate, isTrue);
  });

  test('unknown frame type requires an update', () {
    final compatibility = evaluateGameWireCompatibility(
      frameType: FrameTypeEnum.unknownDefaultOpenApi,
    );

    expect(compatibility.unknownFrameType, isTrue);
    expect(compatibility.requiresUpdate, isTrue);
  });

  test('unknown access degrades conservatively without blocking gameplay', () {
    final compatibility = evaluateGameWireCompatibility(
      access: GameAccess.unknownDefaultOpenApi,
    );

    expect(compatibility.unknownAccess, isTrue);
    expect(compatibility.requiresUpdate, isFalse);
  });
}
