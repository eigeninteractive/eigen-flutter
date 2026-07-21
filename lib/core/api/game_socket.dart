import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:eigen_api/eigen_api.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// One message from a game's socket, or the signal that the socket (re)opened.
///
/// The server never reads from this socket — every client-to-server command
/// rides HTTP — so this is a one-way feed of the message kinds the protocol
/// defines, plus the connection signal the ordering pipeline needs.
sealed class GameSocketEvent {
  const GameSocketEvent();
}

/// The socket just (re)opened.
///
/// Emitted on the first connection and on every reconnect. Nothing is
/// reconciled from this alone: the server states where the game is in the
/// [GameSocketRoster] or [GameSocketSync] that follows, so the pipeline acts on
/// that rather than guessing from the fact of connecting.
final class GameSocketConnected extends GameSocketEvent {
  const GameSocketConnected();
}

/// A pre-game roster snapshot: who is seated and what the game's status is.
///
/// Unversioned and idempotent — the server pushes one on every roster change
/// and one on socket open while the game is still in the waiting room, so a
/// reconnect simply gets the current one.
final class GameSocketRoster extends GameSocketEvent {
  const GameSocketRoster(this.roster);

  final Roster roster;
}

/// Where the game currently is, sent once on a mid-game socket open.
///
/// Hand-parsed rather than generated: unlike [Roster] and [Frame], which appear
/// in HTTP responses and so exist in the OpenAPI document, this message is
/// socket-only and has no generated counterpart.
final class GameSocketSync extends GameSocketEvent {
  const GameSocketSync(this.version);

  /// The newest committed version at the moment the socket opened.
  final int version;
}

/// One versioned frame for the receiving seat.
///
/// Only ever this socket's own seat's view — the server resolves each frame's
/// owner against the roster before sending, so another player's hidden
/// information never crosses the wire.
final class GameSocketFrame extends GameSocketEvent {
  const GameSocketFrame(this.frame);

  final Frame frame;
}

/// Opens a game's socket and keeps it open for the screen's lifetime.
///
/// Reconnects on drop with capped exponential backoff, emitting
/// [GameSocketConnected] each time so the caller can recover whatever it missed
/// while disconnected. It deliberately owns *only* the connection: ordering,
/// gap detection, and recovery are the repository's, because recovering a gap
/// means an HTTP range fetch this layer knows nothing about.
///
/// Auth rides the query string rather than a header because browsers cannot set
/// headers on a WebSocket upgrade. The token is re-read on every connection
/// attempt, so a reconnect after a long background period presents a fresh one.
class GameSocket {
  GameSocket({
    required String baseUrl,
    required FirebaseAuth auth,
    Duration initialBackoff = const Duration(milliseconds: 500),
    Duration maxBackoff = const Duration(seconds: 30),
  }) : _baseUrl = baseUrl,
       _auth = auth,
       _initialBackoff = initialBackoff,
       _maxBackoff = maxBackoff;

  final String _baseUrl;
  final FirebaseAuth _auth;
  final Duration _initialBackoff;
  final Duration _maxBackoff;

  /// Connects to [gameId]'s socket, reconnecting until the subscription is
  /// cancelled.
  ///
  /// The stream never completes on its own and never surfaces a connection
  /// failure as an error: a dropped socket is an expected condition on mobile,
  /// and the recovery for it is the reconnect this already performs. Errors
  /// that are *not* recoverable that way — a malformed message — are logged and
  /// skipped rather than tearing down a working connection.
  Stream<GameSocketEvent> connect(String gameId) async* {
    var backoff = _initialBackoff;

    while (true) {
      final token = await _auth.currentUser?.getIdToken();
      if (token == null) {
        // Signed out, most likely mid-teardown as the auth redirect runs.
        // Nothing to listen to, and retrying cannot help.
        return;
      }

      WebSocketChannel? channel;
      try {
        channel = WebSocketChannel.connect(_socketUri(gameId, token));
        await channel.ready;
        backoff = _initialBackoff;
        yield const GameSocketConnected();

        await for (final message in channel.stream) {
          final event = _decode(message);
          if (event != null) yield event;
        }
      } catch (error, stack) {
        developer.log(
          'game socket for $gameId dropped; reconnecting',
          name: 'eigen.socket',
          error: error,
          stackTrace: stack,
        );
      } finally {
        await channel?.sink.close();
      }

      await Future<void>.delayed(backoff);
      final doubled = backoff * 2;
      backoff = doubled > _maxBackoff ? _maxBackoff : doubled;
    }
  }

  /// `https://host` → `wss://host/api/engine/games/{id}/socket?token=…`.
  Uri _socketUri(String gameId, String token) {
    final base = Uri.parse(_baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/engine/games/$gameId/socket',
      queryParameters: {'token': token},
    );
  }

  /// Decodes one wire message, or null if it is not one we understand.
  ///
  /// An unrecognised `type` is skipped rather than thrown: it means the server
  /// added a message kind this build predates, and dropping it degrades far
  /// better than killing a live game's socket.
  GameSocketEvent? _decode(dynamic message) {
    try {
      final json = jsonDecode(message as String) as Map<String, dynamic>;
      return switch (json['type']) {
        'roster' => GameSocketRoster(Roster.fromJson(json)),
        'frame' => GameSocketFrame(Frame.fromJson(json)),
        'sync' => GameSocketSync(json['version'] as int),
        _ => null,
      };
    } catch (error, stack) {
      developer.log(
        'unreadable game socket message',
        name: 'eigen.socket',
        error: error,
        stackTrace: stack,
      );
      return null;
    }
  }
}
