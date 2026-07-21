import 'dart:async';

import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/engine_call.dart';
import 'package:eigen_flutter/core/api/game_socket.dart';

/// Number of games fetched per lobby page.
const lobbyPageSize = 50;

/// Number of games fetched per history page.
const historyPageSize = 30;

/// Number of games shown in the replay list on a player's profile.
const profileGamesPageSize = 10;

/// Everything a client does to a game: discovery, the waiting room, moves, and
/// the live frame feed.
///
/// Commands all travel over HTTP even while a socket is open - the socket is a
/// one-way feed. That is what makes a command's outcome unambiguous: it is the
/// HTTP status, not something to correlate against a later broadcast.
class GameRepository {
  GameRepository(this._api, this._bots, this._players, this._socket);

  final GamesApi _api;
  final BotsApi _bots;
  final PlayersApi _players;
  final GameSocket _socket;

  // ── Discovery ──────────────────────────────────────────────────────────────

  /// Public games waiting for players, newest first.
  Future<List<GameSummary>> getLobby({int limit = lobbyPageSize}) async {
    final response = await engineCall(() => _api.getLobby(limit: limit));
    return response.data?.games ?? const [];
  }

  /// The caller's own games - live ones first, then finished.
  Future<List<GameSummary>> getMyGames({int limit = historyPageSize}) async {
    final response = await engineCall(() => _api.getMyGames(limit: limit));
    return response.data?.games ?? const [];
  }

  /// One game's metadata and roster.
  ///
  /// Carries the immutable facts a game screen needs once - schema version,
  /// config, timing - so they are fetched rather than streamed. The mutable
  /// parts (status, seats) also arrive live over the socket.
  Future<GameSummary> getGame(String gameId) async {
    final response = await engineCall(() => _api.getGame(gameId: gameId));
    return response.data!;
  }

  /// A player's finished public games - the replay list on their profile.
  ///
  /// Any player, human or bot. Public and finished only, so this exposes
  /// nothing that was not already replayable by anyone holding the game's id.
  Future<List<GameSummary>> getPlayerGames(String playerId, {int? limit}) async {
    final response = await engineCall(
      () => _players.getPlayerGames(playerId: playerId, limit: limit),
    );
    return response.data?.games ?? const [];
  }

  /// The bots available to seat, for this build's schema version.
  Future<List<Bot>> getBots() async {
    final response = await engineCall(() => _bots.getBots());
    return response.data?.bots ?? const [];
  }

  // ── Creating and joining ───────────────────────────────────────────────────

  /// Creates a game and returns its id and shareable short code.
  ///
  /// [rated] is a concrete assertion, not a preference: the caller computes it
  /// from the rules twin and the server validates it rather than coercing, so a
  /// disagreement is a loud 422 instead of a silently unrated game.
  Future<Created> createGame({
    required GameAccess access,
    required int schemaVersion,
    required Object config,
    required int minPlayers,
    required int maxPlayers,
    bool? rated,
    int? turnSeconds,
    int? budgetSeconds,
    int? incrementSeconds,
  }) async {
    final response = await engineCall(
      () => _api.createGame(
        createGame: CreateGame(
          access: access,
          schemaVersion: schemaVersion,
          config: config,
          minPlayers: minPlayers,
          maxPlayers: maxPlayers,
          rated: rated,
          turnSeconds: turnSeconds,
          budgetSeconds: budgetSeconds,
          incrementSeconds: incrementSeconds,
        ),
      ),
    );
    return response.data!;
  }

  /// Creates a private game seated with the caller plus [botIds] and starts it,
  /// in one call.
  ///
  /// Returns the caller's committed v0 frame alongside the ids: the game is
  /// already running before any socket exists, so this response is the only
  /// place that first frame can come from.
  Future<SoloStarted> createSoloGame({
    required int schemaVersion,
    required Object config,
    required int minPlayers,
    required int maxPlayers,
    required List<String> botIds,
    bool? rated,
    int? turnSeconds,
    int? budgetSeconds,
    int? incrementSeconds,
  }) async {
    final response = await engineCall(
      () => _api.createSoloGame(
        createSolo: CreateSolo(
          schemaVersion: schemaVersion,
          config: config,
          minPlayers: minPlayers,
          maxPlayers: maxPlayers,
          botIds: botIds,
          rated: rated,
          turnSeconds: turnSeconds,
          budgetSeconds: budgetSeconds,
          incrementSeconds: incrementSeconds,
        ),
      ),
    );
    return response.data!;
  }

  /// Takes a seat. [clientSchemaVersion] is the newest version this build ships
  /// rules for - the server refuses rather than let an old build mis-parse a
  /// newer game.
  Future<Roster> joinGame(
    String gameId, {
    required int clientSchemaVersion,
    String? commandId,
  }) async {
    final response = await engineCall(
      () => _api.joinGame(
        gameId: gameId,
        join: Join(
          clientSchemaVersion: clientSchemaVersion,
          commandId: commandId,
        ),
      ),
    );
    return response.data!.roster;
  }

  /// Takes a seat using a shared short code rather than a game id.
  Future<Roster> joinGameByCode(
    String shortCode, {
    required int clientSchemaVersion,
    String? commandId,
  }) async {
    final response = await engineCall(
      () => _api.joinGameByCode(
        joinByCode: JoinByCode(
          shortCode: shortCode,
          clientSchemaVersion: clientSchemaVersion,
          commandId: commandId,
        ),
      ),
    );
    return response.data!.roster;
  }

  /// Gives up a seat before the game starts. The creator cancels instead.
  Future<Roster> leaveGame(String gameId, {String? commandId}) async {
    final response = await engineCall(
      () => _api.leaveGame(
        gameId: gameId,
        lobbyCommand: LobbyCommand(commandId: commandId),
      ),
    );
    return response.data!.roster;
  }

  /// Abandons a game that has not started. Creator only.
  Future<Roster> cancelGame(String gameId, {String? commandId}) async {
    final response = await engineCall(
      () => _api.cancelGame(
        gameId: gameId,
        lobbyCommand: LobbyCommand(commandId: commandId),
      ),
    );
    return response.data!.roster;
  }

  /// Seats a bot alongside the humans. Creator only, pre-start.
  Future<Roster> addBot(
    String gameId, {
    required String botId,
    String? commandId,
  }) async {
    final response = await engineCall(
      () => _api.addBot(
        gameId: gameId,
        addBot: AddBot(botId: botId, commandId: commandId),
      ),
    );
    return response.data!.roster;
  }

  /// Starts a ready game. Creator only.
  ///
  /// Returns the committed version; the opening frames reach every seat over
  /// their own socket, since a start has no single acting seat.
  Future<int> startGame(String gameId, {String? commandId}) async {
    final response = await engineCall(
      () => _api.startGame(
        gameId: gameId,
        lobbyCommand: LobbyCommand(commandId: commandId),
      ),
    );
    return response.data!.version;
  }

  // ── Playing ────────────────────────────────────────────────────────────────

  /// Submits a move for [seat] against [expectedVersion].
  ///
  /// [seat] is the caller's own index, verified against the roster server-side.
  /// [expectedVersion] is the optimistic lock: if the board moved on in a way
  /// this seat could see, the move is refused with [ErrorCode.stateUpdated]
  /// rather than applied to a state the player never saw.
  ///
  /// Reusing a [commandId] replays the stored response instead of re-executing,
  /// so a resubmitted move cannot land twice.
  ///
  /// The returned [CommandAccepted.frame] is this seat's own committed view.
  /// Feed it to [frames] so the move renders without waiting on the socket -
  /// see that method for why both paths carry it.
  Future<CommandAccepted> submitAction({
    required String gameId,
    required int seat,
    required int expectedVersion,
    required Object? data,
    String? commandId,
  }) async {
    final response = await engineCall(
      () => _api.submitAction(
        gameId: gameId,
        action: Action(
          seat: seat,
          data: data,
          expectedVersion: expectedVersion,
          commandId: commandId,
        ),
      ),
    );
    return response.data!;
  }

  /// Resigns [seat] from a live game.
  Future<CommandAccepted> forfeitGame({
    required String gameId,
    required int seat,
    String? commandId,
  }) async {
    final response = await engineCall(
      () => _api.forfeitGame(
        gameId: gameId,
        forfeit: Forfeit(seat: seat, commandId: commandId),
      ),
    );
    return response.data!;
  }

  /// Frames in `[from, to]` for the caller's seat, version-ascending.
  ///
  /// Backs both gap recovery and replay. A non-participant may read a finished
  /// public game, which is what makes spectating a replay possible.
  Future<List<Frame>> getFrames(
    String gameId, {
    int from = 0,
    int? to,
  }) async {
    final response = await engineCall(
      () => _api.getFrames(gameId: gameId, from: from, to: to),
    );
    return response.data?.frames ?? const [];
  }

  // ── The live feed ──────────────────────────────────────────────────────────

  /// The game's live events: roster snapshots pre-game, then frames in strict
  /// version order with any gaps filled.
  ///
  /// Frames are append-only server-side, one per seat per version, which is
  /// what makes this recoverable: a socket may drop or a reconnect may miss
  /// events, but a version jump is detected here and the missing frames are
  /// fetched and emitted in order first. A game therefore always animates
  /// through every transition rather than snapping past one.
  ///
  /// Duplicates and stale frames are dropped, which is what lets the same frame
  /// arrive twice safely. That matters because it does: a move's own frame
  /// rides the [submitAction] response *and* fans out over the socket. Pass the
  /// response's frame to [inject] and whichever copy arrives second is
  /// discarded by version. On the socket-less paths - a freshly created solo
  /// game, or a move made while the socket is mid-reconnect - the injected copy
  /// is the only one, which is why the response carries it at all.
  ///
  /// The first frame seen is emitted as-is: a cold load snaps to the present
  /// rather than replaying the whole game.
  Stream<GameSocketEvent> events(
    String gameId, {
    Stream<Frame>? inject,
  }) {
    late StreamController<GameSocketEvent> controller;
    int? lastVersion;
    StreamSubscription<GameSocketEvent>? socketSub;
    StreamSubscription<Frame>? injectSub;

    // Serialises handling so emissions stay in version order however bursts of
    // socket events interleave with the async gap fetches they trigger.
    var pipeline = Future<void>.value();

    void emit(Frame frame) {
      lastVersion = frame.version;
      controller.add(GameSocketFrame(frame));
    }

    Future<void> handleFrame(Frame frame) async {
      if (controller.isClosed) return;
      final last = lastVersion;
      if (last == null) {
        emit(frame);
        return;
      }
      if (frame.version <= last) return;
      if (frame.version > last + 1) {
        final missed = await getFrames(
          gameId,
          from: last + 1,
          to: frame.version - 1,
        );
        for (final gap in missed) {
          if (controller.isClosed) return;
          if (gap.version > lastVersion!) emit(gap);
        }
      }
      if (controller.isClosed) return;
      if (frame.version > lastVersion!) emit(frame);
    }

    /// After a reconnect, ask for everything past the cursor. Any real gap is
    /// then filled by [handleFrame] exactly as a live jump would be.
    Future<void> resync() async {
      final cursor = lastVersion;
      if (cursor == null || controller.isClosed) return;
      for (final frame in await getFrames(gameId, from: cursor + 1)) {
        if (controller.isClosed) return;
        if (frame.version > lastVersion!) emit(frame);
      }
    }

    void enqueue(Future<void> Function() work) {
      pipeline = pipeline.then((_) => work()).catchError((Object error) {
        if (!controller.isClosed) controller.addError(error);
      });
    }

    controller = StreamController<GameSocketEvent>(
      onListen: () {
        socketSub = _socket.connect(gameId).listen((event) {
          switch (event) {
            case GameSocketConnected():
              controller.add(event);
              enqueue(resync);
            case GameSocketRoster():
              // Unversioned and idempotent - pass straight through.
              controller.add(event);
            case GameSocketFrame(:final frame):
              enqueue(() => handleFrame(frame));
          }
        }, onError: controller.addError);

        injectSub = inject?.listen(
          (frame) => enqueue(() => handleFrame(frame)),
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await socketSub?.cancel();
        await injectSub?.cancel();
      },
    );

    return controller.stream;
  }
}
