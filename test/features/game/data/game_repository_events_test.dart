import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:dio/dio.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/game_socket.dart';
import 'package:eigen_flutter/features/game/data/game_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// One frame's wire JSON. Only the fields the pipeline reasons about matter.
Map<String, dynamic> _frameJson(int version) => {
  'type': 'frame',
  'version': version,
  'data': <String, dynamic>{'v': version},
  'pending_players': <int>[0],
  'deadline': null,
  'player_times': null,
};

Frame _frame(int version) => Frame.fromJson(_frameJson(version));

/// Serves `GET .../frames?from=&to=` from an in-memory version range, so the
/// repository's gap recovery runs for real against a stubbed wire.
class _FramesAdapter implements HttpClientAdapter {
  _FramesAdapter(this.available);

  /// Versions the server would return.
  final List<int> available;

  /// Every `[from, to]` the repository asked for, in order.
  final requests = <({int from, int? to})>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final from = int.parse(options.queryParameters['from'].toString());
    final rawTo = options.queryParameters['to'];
    final to = rawTo == null ? null : int.parse(rawTo.toString());
    requests.add((from: from, to: to));

    final frames = available
        .where((v) => v >= from && (to == null || v <= to))
        .map(_frameJson)
        .toList();
    return ResponseBody.fromString(
      jsonEncode({'frames': frames}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A socket the test drives by hand. Dart's implicit interfaces make this a
/// stub without needing an abstraction in the production code.
class _ScriptedSocket implements GameSocket {
  final _controller = StreamController<GameSocketEvent>();

  void emit(GameSocketEvent event) => _controller.add(event);

  @override
  Stream<GameSocketEvent> connect(String gameId) => _controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

({GameRepository repo, _ScriptedSocket socket, _FramesAdapter adapter}) _build({
  List<int> available = const [],
}) {
  final adapter = _FramesAdapter(available);
  final dio = Dio(BaseOptions(baseUrl: 'https://engine.test'))
    ..httpClientAdapter = adapter;
  final socket = _ScriptedSocket();
  return (
    repo: GameRepository(GamesApi(dio), BotsApi(dio), PlayersApi(dio), socket),
    socket: socket,
    adapter: adapter,
  );
}

/// Versions of the frames emitted on [stream], in order.
Future<List<int>> _versions(
  Stream<GameSocketEvent> stream,
  Future<void> Function() drive,
) async {
  final seen = <int>[];
  final sub = stream.listen((e) {
    if (e is GameSocketFrame) seen.add(e.frame.version);
  });
  await drive();
  // Long enough for the stubbed gap fetches the pipeline may issue to land.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await sub.cancel();
  return seen;
}

void main() {
  test('emits the first frame as-is, without replaying history', () async {
    // A cold load snaps to the present: joining at v7 must not replay v0-v6.
    final t = _build(available: [0, 1, 2, 3, 4, 5, 6, 7]);

    final seen = await _versions(t.repo.events('g'), () async {
      t.socket.emit(GameSocketFrame(_frame(7)));
    });

    check(seen).deepEquals([7]);
    check(t.adapter.requests).isEmpty();
  });

  test('passes consecutive frames straight through', () async {
    final t = _build();

    final seen = await _versions(t.repo.events('g'), () async {
      for (var v = 3; v <= 5; v++) {
        t.socket.emit(GameSocketFrame(_frame(v)));
      }
    });

    check(seen).deepEquals([3, 4, 5]);
    check(t.adapter.requests).isEmpty();
  });

  test('fills a gap in order before the frame that revealed it', () async {
    // Every transition must be seen so the game can animate through each one.
    final t = _build(available: [1, 2, 3]);

    final seen = await _versions(t.repo.events('g'), () async {
      t.socket.emit(GameSocketFrame(_frame(0)));
      t.socket.emit(GameSocketFrame(_frame(4)));
    });

    check(seen).deepEquals([0, 1, 2, 3, 4]);
    check(t.adapter.requests).deepEquals([(from: 1, to: 3)]);
  });

  test('drops duplicate and stale frames', () async {
    // The same frame legitimately arrives twice: over the socket and on the
    // action response. Whichever loses the race must be discarded silently.
    final t = _build();

    final seen = await _versions(t.repo.events('g'), () async {
      for (final v in [4, 5, 5, 4, 3, 6]) {
        t.socket.emit(GameSocketFrame(_frame(v)));
      }
    });

    check(seen).deepEquals([4, 5, 6]);
  });

  test('an injected frame renders without waiting for the socket', () async {
    // The socket-less paths: a freshly created solo game, and a move made
    // while the socket is mid-reconnect.
    final t = _build();
    final injected = StreamController<Frame>();

    final seen = await _versions(t.repo.events('g', inject: injected.stream), () async {
      injected.add(_frame(0));
      await Future<void>.delayed(Duration.zero);
      injected.add(_frame(1));
    });

    check(seen).deepEquals([0, 1]);
    check(t.adapter.requests).isEmpty();
    await injected.close();
  });

  test('the socket copy of an injected frame is dropped', () async {
    final t = _build();
    final injected = StreamController<Frame>();

    final seen = await _versions(t.repo.events('g', inject: injected.stream), () async {
      injected.add(_frame(2));
      await Future<void>.delayed(Duration.zero);
      t.socket.emit(GameSocketFrame(_frame(2)));
    });

    check(seen).deepEquals([2]);
    await injected.close();
  });

  test('resyncs from the version cursor on reconnect', () async {
    // The server sends no backlog on a mid-game open, so the client must ask.
    final t = _build(available: [3, 4, 5]);

    final seen = await _versions(t.repo.events('g'), () async {
      t.socket.emit(GameSocketFrame(_frame(2)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      t.socket.emit(const GameSocketConnected());
    });

    check(seen).deepEquals([2, 3, 4, 5]);
    check(t.adapter.requests).deepEquals([(from: 3, to: null)]);
  });

  test('does not resync before any frame has been seen', () async {
    // The first connect has no cursor to resync from; fetching would replay
    // the whole game rather than snapping to the present.
    final t = _build(available: [0, 1, 2]);

    final seen = await _versions(t.repo.events('g'), () async {
      t.socket.emit(const GameSocketConnected());
    });

    check(seen).isEmpty();
    check(t.adapter.requests).isEmpty();
  });

  test('passes roster snapshots through unversioned', () async {
    final t = _build();
    final rosters = <String>[];

    final stream = t.repo.events('g');
    final sub = stream.listen((e) {
      if (e is GameSocketRoster) rosters.add(e.roster.status.value);
    });
    t.socket.emit(
      GameSocketRoster(
        Roster.fromJson({
          'type': 'roster',
          'status': 'ready',
          'players': <dynamic>[],
        }),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    check(rosters).deepEquals(['ready']);
  });
}
