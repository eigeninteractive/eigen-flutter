import 'package:eigen_flutter/core/api/game_socket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildGameSocketUri', () {
    test('uses wss and the token query for an HTTPS Worker origin', () {
      final uri = buildGameSocketUri(
        apiBaseUrl: 'https://game.example',
        gameId: 'game 1',
        token: 'header.payload+/=',
      );

      expect(uri.scheme, 'wss');
      expect(uri.host, 'game.example');
      expect(uri.path, '/api/engine/games/game%201/socket');
      expect(uri.queryParameters, {'token': 'header.payload+/='});
    });

    test('uses ws for a local HTTP Worker', () {
      final uri = buildGameSocketUri(
        apiBaseUrl: 'http://localhost:8787',
        gameId: 'g1',
        token: 'token',
      );

      expect(
        uri.toString(),
        'ws://localhost:8787/api/engine/games/g1/socket?token=token',
      );
    });

    test('rejects a non-HTTP API base URL', () {
      expect(
        () => buildGameSocketUri(
          apiBaseUrl: 'ftp://game.example',
          gameId: 'g1',
          token: 'token',
        ),
        throwsArgumentError,
      );
    });
  });
}
