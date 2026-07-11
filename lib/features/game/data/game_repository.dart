import 'dart:async';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_engine/core/errors/engine_exception.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/features/game/data/models/bot_info.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
import 'package:eigen_engine/features/game/data/models/observation.dart';
import 'package:eigen_engine/features/game/data/models/participant.dart';
import 'package:eigen_engine/features/rating/data/models/rating_change.dart';
import 'package:eigen_engine/shared/data/db_guard.dart';

/// Number of games fetched per lobby page.
const lobbyPageSize = 50;

/// Number of games fetched per history page.
const historyPageSize = 30;

/// Repository for game operations.
///
/// Game-rule operations (start, action, forfeit, expiry, local-bot moves) go
/// through the `game` Edge Function, which runs the TypeScript gameModule and
/// commits via gated RPCs. Lobby/discovery/bot-catalog operations and reads stay
/// on PostgREST RPCs. Clients read observations via Realtime subscriptions.
class GameRepository {
  GameRepository(this._client);

  final SupabaseClient _client;

  /// Live observation pipelines by game id. [observationStream] registers its
  /// enqueue callback here so [submitAction] can feed the caller's committed
  /// frame (returned on the action response) into the same version-deduped
  /// pipeline the Realtime events flow through — the own-move frame renders
  /// off the HTTP response instead of waiting for the Realtime hop, and the
  /// duplicate Realtime event is dropped by the pipeline's version check.
  final _observationInjectors = <String, Set<void Function(Observation)>>{};

  /// Invokes an `engine` Edge Function game route.
  ///
  /// On failure the function returns `{ "error": "<message>", "code"?: "EIGxx" }`
  /// with a non-2xx status; supabase throws [FunctionException] carrying that
  /// body in [FunctionException.details]. It is rethrown as a structured
  /// [EngineException] so callers (and [humanize]) can dispatch on the stable
  /// code. A transport failure (no server response) propagates as the
  /// underlying network exception, distinguishing "the server said no" from
  /// "the outcome is unknown".
  Future<dynamic> _invokeEngine(String route, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(
        'engine/game/$route',
        body: body,
      );
      return res.data;
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'Edge function error (status ${e.status})';
      final code = details is Map && details['code'] is String
          ? details['code'] as String
          : null;
      throw EngineException(message, code: code);
    }
  }

  /// Creates a new game via RPC.
  ///
  /// Returns the game ID.
  ///
  /// [turnSeconds] and [budgetSeconds] are mutually exclusive timing modes.
  /// Passing both throws on the server.
  ///
  /// [rated] is a concrete assertion, not a preference: the caller computes it
  /// from the rating rules (the Dart twin of `GameRules.ratingPool` (TS), plus the
  /// guest check) and the server validates it, rejecting a mismatch rather than
  /// silently coercing. Pass `false` whenever the config is ineligible or the
  /// caller is a guest.
  Future<String> createGame({
    GameAccess access = GameAccess.public,
    int? turnSeconds,
    int? budgetSeconds,
    int? incrementSeconds,
    required int minPlayers,
    required int maxPlayers,
    Map<String, dynamic> config = const {},
    bool rated = true,
    required int schemaVersion,
  }) async {
    final data = await _invokeEngine('create', {
      'access': access.name,
      'turn_seconds': ?turnSeconds,
      'budget_seconds': ?budgetSeconds,
      'increment_seconds': ?incrementSeconds,
      'min_players': minPlayers,
      'max_players': maxPlayers,
      'config': config,
      'rated': rated,
      'schema_version': schemaVersion,
    });
    return (data as Map<String, dynamic>)['game_id'] as String;
  }

  /// Joins a game via RPC.
  ///
  /// [clientSchemaVersion] is the running build's highest supported game schema
  /// ([GameModule.latestSchemaVersion]); the server refuses to seat the caller in a
  /// game whose `schema_version` exceeds it, so the client never becomes a
  /// participant in a game it cannot render.
  ///
  /// Returns the participant ID.
  Future<String> joinGame(
    String gameId, {
    required int clientSchemaVersion,
  }) async {
    final result = await dbGuard(
      () => _client.rpc(
        'app_join_game',
        params: {
          'p_game_id': gameId,
          'p_client_schema_version': clientSchemaVersion,
        },
      ),
    );
    return result as String;
  }

  /// Joins a game by short code via RPC.
  ///
  /// [clientSchemaVersion] gates the join exactly as in [joinGame] — the
  /// by-code and deep-link paths cannot inspect the game before joining, so the
  /// server enforces the schema check before seating the caller.
  ///
  /// Returns the game ID.
  Future<String> joinGameByCode(
    String code, {
    required int clientSchemaVersion,
  }) async {
    final result = await dbGuard(
      () => _client.rpc(
        'app_join_game_by_code',
        params: {
          'p_code': code,
          'p_client_schema_version': clientSchemaVersion,
        },
      ),
    );
    return result as String;
  }

  /// Starts a game via the engine function (host only). The function computes
  /// the initial state + observation slices in TS and commits them.
  Future<void> startGame(String gameId) async {
    await _invokeEngine('start', {'game_id': gameId});
  }

  /// Submits an action via RPC.
  ///
  /// Returns as soon as the server accepts the action. The response carries
  /// the caller's committed observation frame, which is fed into any live
  /// [observationStream] pipeline for the game — the own-move frame renders
  /// off the HTTP response (typically ahead of the Realtime event, whose
  /// duplicate the pipeline then drops by version). State still flows to the
  /// UI exclusively through the stream; the response body is never a second
  /// state channel.
  ///
  /// On an optimistic-lock conflict the server raises a `Stale state` error,
  /// which the UI surfaces as a humanized "the game updated — try again" message.
  Future<void> submitAction({
    required String gameId,
    required Map<String, dynamic> actionData,
    required int expectedVersion,
  }) async {
    final data = await _invokeEngine('action', {
      'game_id': gameId,
      'data': actionData,
      'expected_version': expectedVersion,
    });
    _injectOwnFrame(gameId, data);
  }

  /// Feeds the committed frame from an action response into the game's live
  /// observation pipelines, if any.
  ///
  /// A malformed frame is logged and dropped rather than thrown: the action
  /// itself committed, and the Realtime path still delivers the frame — a
  /// failure of this latency shortcut must not surface as a submit failure.
  void _injectOwnFrame(String gameId, dynamic responseData) {
    final injectors = _observationInjectors[gameId];
    if (injectors == null || injectors.isEmpty) return;
    final json = responseData is Map<String, dynamic>
        ? responseData['observation']
        : null;
    if (json is! Map<String, dynamic>) return;
    try {
      final observation = Observation.fromJson(json);
      for (final inject in [...injectors]) {
        inject(observation);
      }
    } catch (e, s) {
      developer.log(
        'Failed to parse action-response observation frame',
        name: 'eigen_engine.game_repository',
        level: 900,
        error: e,
        stackTrace: s,
      );
    }
  }

  /// Fetches the outcomes for a completed game.
  ///
  /// Returns one [GameOutcome] per participant. Empty for games that are not
  /// yet finished. Call this once when [Game.status] transitions to finished.
  Future<List<GameOutcome>> getGameOutcomes(String gameId) async {
    final response = await dbGuard(
      () => _client
          .from('game_outcomes')
          .select()
          .eq('game_id', gameId)
          .order('player_index'),
    );
    return response.map((json) => GameOutcome.fromJson(json)).toList();
  }

  /// Gets public games that are open for joining (lobby).
  ///
  /// Delegates to the [app_lobby_games] RPC, which filters full games via a
  /// SQL [HAVING] clause on the participant count — an aggregate comparison
  /// that PostgREST cannot express as a plain [WHERE] filter.
  ///
  /// Returns both [GameStatus.waiting] and [GameStatus.ready] games so that
  /// variable-player games (e.g. poker) remain visible after reaching their
  /// minimum player count, as long as slots remain.
  ///
  /// Includes the current user's own games so they can cancel them.
  /// Pass [cursor] to fetch games older than a given [DateTime] for pagination.
  ///
  /// Each entry includes participant details (user IDs and indices) so the
  /// lobby screen can resolve player identities via the cached
  /// [playerInfoCacheProvider] without extra queries.
  Future<
    List<({Game game, List<Participant> participants, bool isParticipant})>
  >
  getLobbyGames({DateTime? cursor}) =>
      _getJoinableGames('app_lobby_games', cursor);

  /// Gets friends-access games that are open for joining, including the
  /// current user's own rooms.
  Future<
    List<({Game game, List<Participant> participants, bool isParticipant})>
  >
  getFriendsGames({DateTime? cursor}) =>
      _getJoinableGames('app_friends_games', cursor);

  /// Shared fetch/parse for the two lobby RPCs, which return identical shapes.
  Future<
    List<({Game game, List<Participant> participants, bool isParticipant})>
  >
  _getJoinableGames(String rpcName, DateTime? cursor) async {
    final response = await dbGuard(
      () => _client.rpc(
        rpcName,
        params: {
          if (cursor != null) 'p_cursor': cursor.toIso8601String(),
          'p_limit': lobbyPageSize,
        },
      ),
    );

    return (response as List<dynamic>).map((item) {
      final json = item as Map<String, dynamic>;
      final participantsJson = (json['participants'] as List<dynamic>?) ?? [];
      final participants = participantsJson
          .cast<Map<String, dynamic>>()
          .map((p) => Participant.fromJson(p))
          .toList();
      final isParticipant = json['is_participant'] as bool;
      return (
        game: Game.fromJson(json),
        participants: participants,
        isParticipant: isParticipant,
      );
    }).toList();
  }

  /// Triggers expiry of the current turn for a timed game.
  ///
  /// Call this when the client detects [Observation.turnDeadline] has passed.
  /// The server re-validates under a row lock, so duplicate calls from the
  /// client and the pg_cron job are both safe.
  Future<void> triggerTurnExpiry(String gameId) async {
    await _invokeEngine('expire', {'game_id': gameId});
  }

  /// Leaves a waiting or ready game (non-creator participants only).
  ///
  /// The creator cannot leave — use [cancelGame] instead.
  Future<void> leaveGame(String gameId) async {
    await dbGuard(
      () => _client.rpc('app_leave_game', params: {'p_game_id': gameId}),
    );
  }

  /// Cancels a waiting game (creator only).
  Future<void> cancelGame(String gameId) async {
    await dbGuard(
      () => _client.rpc('app_cancel_game', params: {'p_game_id': gameId}),
    );
  }

  /// Forfeits an active game.
  ///
  /// Any participant may forfeit regardless of whose turn it is. No version
  /// check — forfeiting is an unconditional intent, and the server's row
  /// lock already serialises it against concurrent actions.
  Future<void> forfeitGame(String gameId) async {
    await _invokeEngine('forfeit', {'game_id': gameId});
  }

  /// Fetches the current user's finished and aborted games for the history view.
  ///
  /// Embeds [game_outcomes] for the win/loss result and [rating_history] for
  /// per-pool rating deltas. RLS on [rating_history] automatically filters the
  /// embedded rows to the current user — no explicit filter needed.
  ///
  /// Returns entries ordered by [Game.finishedAt] descending. Pass [cursor] to
  /// fetch games older than the given [DateTime] for cursor-based pagination.
  Future<
    List<({Game game, OutcomeResult? myResult, RatingChange? ratingChange})>
  >
  getHistoryGameEntries({DateTime? cursor}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    var query = _client
        .from('games')
        .select(
          '*, '
          'participants!inner(user_id, player_index), '
          'game_outcomes(player_index, result), '
          'rating_history(pool, display_before, display_after, display_change, created_at)',
        )
        .eq('participants.user_id', userId)
        .inFilter('status', ['finished', 'aborted']);

    if (cursor != null) {
      query = query.lt('finished_at', cursor.toIso8601String());
    }

    final response = await dbGuard(
      () => query.order('finished_at', ascending: false).limit(historyPageSize),
    );

    return response.map((j) {
      final participant = (j['participants'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((p) => p['user_id'] == userId);
      final myPlayerIndex = participant['player_index'] as int;

      final outcomes = (j['game_outcomes'] as List)
          .cast<Map<String, dynamic>>();
      final myOutcomeJson = outcomes
          .where((o) => o['player_index'] == myPlayerIndex)
          .firstOrNull;
      final myResult = myOutcomeJson == null
          ? null
          : OutcomeResult.values.byName(myOutcomeJson['result'] as String);

      final historyRows = (j['rating_history'] as List)
          .cast<Map<String, dynamic>>();
      final ratingChange = historyRows.isEmpty
          ? null
          : RatingChange.fromJson(historyRows.first);

      return (
        game: Game.fromJson(j),
        myResult: myResult,
        ratingChange: ratingChange,
      );
    }).toList();
  }

  // ── Bots ───────────────────────────────────────────────────────────────────

  /// Bots available for this deployment (display-safe columns), for the
  /// solo play and "Add bot" pickers.
  Future<List<BotInfo>> getBots() async {
    final result = await dbGuard(() => _client.rpc('app_bots'));
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(BotInfo.fromJson)
        .toList();
  }

  /// Creates a solo game: the caller plus [botIds] (local and/or server, in seat
  /// order), unrated. The EF gates each bot's config seatability
  /// ([GameRules.botSeatable]) in TS, then `engine_create_solo_game` creates +
  /// seats and leaves the game `ready`; the engine `start` route then computes the
  /// initial state and begins play. Returns the game ID.
  Future<String> createSoloGame({
    required List<String> botIds,
    required int schemaVersion,
    int? turnSeconds,
    int? budgetSeconds,
    int? incrementSeconds,
    Map<String, dynamic> config = const {},
  }) async {
    final data = await _invokeEngine('create-solo', {
      'bot_ids': botIds,
      'schema_version': schemaVersion,
      'turn_seconds': ?turnSeconds,
      'budget_seconds': ?budgetSeconds,
      'increment_seconds': ?incrementSeconds,
      'config': config,
    });
    final gameId = (data as Map<String, dynamic>)['game_id'] as String;
    await startGame(gameId);
    return gameId;
  }

  /// Adds a server bot to a multiplayer waiting/ready game (creator only). The EF
  /// gates config seatability ([GameRules.botSeatable]) before seating.
  Future<void> addBotToGame({
    required String gameId,
    required String botId,
  }) async {
    await _invokeEngine('add-bot', {'game_id': gameId, 'bot_id': botId});
  }

  /// Submits a local bot's move on its behalf (client-driven, solo games only).
  ///
  /// Keyed by [playerIndex] (the seat), so the same local bot may fill several
  /// seats in one solo game.
  Future<void> submitLocalBotAction({
    required String gameId,
    required int playerIndex,
    required Map<String, dynamic> actionData,
    required int expectedVersion,
  }) async {
    await _invokeEngine('local-bot-action', {
      'game_id': gameId,
      'player_index': playerIndex,
      'data': actionData,
      'expected_version': expectedVersion,
    });
  }

  /// Fetches a bot seat's latest [Observation] for local play, server-gated to
  /// the sole human of a solo game. The RPC returns `SETOF observations` — the
  /// same shape as a human's own observation — already bounded to the seat's
  /// latest frame (a bot acts on the current frame; it has no use for
  /// history), so this reads it with [maybeSingle] exactly like
  /// [getObservation]: null when no row exists yet.
  Future<Observation?> getLocalBotObservation({
    required String gameId,
    required int playerIndex,
  }) async {
    final response = await dbGuard(
      () => _client
          .rpc(
            'app_local_bot_observation',
            params: {'p_game_id': gameId, 'p_player_index': playerIndex},
          )
          .maybeSingle(),
    );

    if (response == null) return null;
    return Observation.fromJson(response);
  }

  /// Gets the participants of a game — ephemeral, per-game data (seat + identity
  /// ids + type). RLS restricts rows to games the caller can see. A bot seat's
  /// reference data (display via [PlayerInfo], capability/config via the cached
  /// bot catalog) is resolved separately by id, not joined here.
  Future<List<Participant>> getParticipants(String gameId) async {
    final response = await dbGuard(
      () => _client
          .from('participants')
          .select()
          .eq('game_id', gameId)
          .order('player_index'),
    );
    return response.map(Participant.fromJson).toList();
  }

  /// Gets the current user's latest observation frame for a game.
  ///
  /// Observations are append-only (one row per seat per state version), so
  /// "the observation" means the highest-version row. RLS restricts results
  /// to the authenticated user's rows, so no explicit user_id filter is
  /// needed.
  Future<Observation?> getObservation(String gameId) async {
    final response = await dbGuard(
      () => _client
          .from('observations')
          .select()
          .eq('game_id', gameId)
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle(),
    );

    if (response == null) return null;
    return Observation.fromJson(response);
  }

  /// Gets a game's current metadata row, or null when the row is not
  /// visible to the caller (RLS) or does not exist.
  ///
  /// Used by [gameStream] as its fetch-on-subscribe snapshot.
  Future<Game?> getGame(String gameId) async {
    final response = await dbGuard(
      () => _client.from('games').select().eq('id', gameId).maybeSingle(),
    );
    if (response == null) return null;
    return Game.fromJson(response);
  }

  /// The caller's missed observation frames in `(after, before)` exclusive,
  /// version-ascending — the gap-recovery fetch for [observationStream].
  Future<List<Observation>> _fetchMissedObservations(
    String gameId, {
    required int after,
    required int before,
  }) async {
    final rows = await dbGuard(
      () => _client
          .from('observations')
          .select()
          .eq('game_id', gameId)
          .gt('version', after)
          .lt('version', before)
          .order('version', ascending: true),
    );
    return rows.map(Observation.fromJson).toList();
  }

  /// Subscribes to the caller's observation frames for a game, delivered in
  /// **version order with gaps recovered**.
  ///
  /// Frames arrive on the caller's private broadcast topic
  /// `game:{gameId}:user:{userId}` (sent by a database trigger on
  /// observation inserts; RLS on `realtime.messages` restricts who may join
  /// the topic). Observations are append-only server-side (one row per seat
  /// per state version), which is what makes this stream reliable: Realtime
  /// can drop or reorder broadcast messages, but a version jump is detected
  /// and the missing rows are fetched and emitted in order, so a live client
  /// sees every transition and can animate through each one. Duplicates and
  /// stale events are dropped.
  ///
  /// The first emission (on subscribe, and the re-fetch on every reconnect)
  /// is the seat's *latest* frame — a cold load snaps to now rather than
  /// replaying history; if the reconnect fetch reveals a gap, the missed
  /// frames are emitted in order first. RLS restricts fetched rows to the
  /// authenticated user's own.
  Stream<Observation> observationStream({required String gameId}) {
    final userId = _client.auth.currentUser?.id;
    // Signed out (e.g. session expired mid-game) — emit nothing rather than
    // crash; the auth redirect tears the screen down momentarily.
    if (userId == null) return const Stream.empty();

    late RealtimeChannel channel;
    late StreamController<Observation> controller;
    int? lastVersion;
    // Serialises frame handling (a gap fetch is async) so emissions stay in
    // version order no matter how bursts of events interleave with fetches.
    var pipeline = Future<void>.value();

    Future<void> handle(Observation obs) async {
      if (controller.isClosed) return;
      final last = lastVersion;
      if (last == null) {
        // Cold baseline: the first frame seen is emitted as-is (no history
        // replay); everything after it is ordered and gap-filled.
        lastVersion = obs.version;
        controller.add(obs);
        return;
      }
      if (obs.version <= last) return;
      if (obs.version > last + 1) {
        final missed = await _fetchMissedObservations(
          gameId,
          after: last,
          before: obs.version,
        );
        for (final frame in missed) {
          if (controller.isClosed) return;
          if (frame.version > lastVersion!) {
            lastVersion = frame.version;
            controller.add(frame);
          }
        }
      }
      if (controller.isClosed) return;
      if (obs.version > lastVersion!) {
        lastVersion = obs.version;
        controller.add(obs);
      }
    }

    void enqueue(Observation obs) {
      pipeline = pipeline.then((_) => handle(obs)).catchError((Object e) {
        if (!controller.isClosed) controller.addError(e);
      });
    }

    // Registered so submitAction can inject the caller's own committed frame
    // (from the action response) into this same pipeline — see
    // [_observationInjectors].
    final injectors = _observationInjectors.putIfAbsent(gameId, () => {});
    injectors.add(enqueue);

    void fetchLatest() {
      getObservation(gameId).then(
        (obs) {
          if (obs != null) enqueue(obs);
        },
        onError: (Object e) {
          if (!controller.isClosed) controller.addError(e);
        },
      );
    }

    controller = StreamController<Observation>(
      onCancel: () {
        injectors.remove(enqueue);
        if (injectors.isEmpty) _observationInjectors.remove(gameId);
        channel.unsubscribe();
      },
    );

    channel =
        _client.channel(
            'game:$gameId:user:$userId',
            opts: const RealtimeChannelConfig(private: true),
          )
          ..onBroadcast(
            event: 'observation',
            callback: (payload) {
              if (controller.isClosed) return;
              final record = payload['payload'];
              if (record is Map) {
                try {
                  enqueue(
                    Observation.fromJson(Map<String, dynamic>.from(record)),
                  );
                } on Object {
                  // Undecodable frame (e.g. a future slim/oversize fallback
                  // payload): treat it as a wake-up and fetch instead; the
                  // pipeline orders and gap-fills as usual.
                  fetchLatest();
                }
              }
            },
          )
          ..subscribe((status, error) {
            switch (status) {
              case RealtimeSubscribeStatus.subscribed:
                // Initial connect and every reconnect: fetch the latest frame so
                // nothing stays missed while disconnected (a gap it reveals is
                // back-filled by the pipeline).
                fetchLatest();
              case RealtimeSubscribeStatus.channelError:
              case RealtimeSubscribeStatus.timedOut:
                if (!controller.isClosed) {
                  controller.addError(
                    error ?? Exception('Realtime subscription failed'),
                  );
                }
              case RealtimeSubscribeStatus.closed:
                break;
            }
          });

    return controller.stream;
  }

  /// Subscribes to game metadata updates on the private broadcast topic
  /// `game:{gameId}` (sent by a database trigger on games UPDATEs — all of
  /// which are lifecycle transitions such as opponents joining or the game
  /// ending).
  ///
  /// Emits the current game on subscribe and re-fetches on every reconnect;
  /// channel errors propagate as stream errors so Riverpod's retry mechanism
  /// can schedule a reconnect with exponential backoff. Latest-state snapshot
  /// semantics are all this needs, unlike [observationStream], which must
  /// deliver every frame and therefore orders and gap-fills.
  ///
  /// An empty snapshot (row not visible yet, or deleted) is skipped rather
  /// than emitted as an error — the stream simply keeps its last value.
  Stream<Game> gameStream(String gameId) {
    late RealtimeChannel channel;
    late StreamController<Game> controller;

    void fetchCurrent() {
      getGame(gameId).then(
        (game) {
          if (game != null && !controller.isClosed) controller.add(game);
        },
        onError: (Object e) {
          if (!controller.isClosed) controller.addError(e);
        },
      );
    }

    controller = StreamController<Game>(onCancel: () => channel.unsubscribe());

    channel =
        _client.channel(
            'game:$gameId',
            opts: const RealtimeChannelConfig(private: true),
          )
          ..onBroadcast(
            event: 'game',
            callback: (payload) {
              if (controller.isClosed) return;
              final record = payload['payload'];
              if (record is Map) {
                controller.add(
                  Game.fromJson(Map<String, dynamic>.from(record)),
                );
              }
            },
          )
          ..subscribe((status, error) {
            switch (status) {
              case RealtimeSubscribeStatus.subscribed:
                fetchCurrent();
              case RealtimeSubscribeStatus.channelError:
              case RealtimeSubscribeStatus.timedOut:
                if (!controller.isClosed) {
                  controller.addError(
                    error ?? Exception('Realtime subscription failed'),
                  );
                }
              case RealtimeSubscribeStatus.closed:
                break;
            }
          });

    return controller.stream;
  }

  /// Fetches the current user's waiting/ready/active games with the
  /// structural data needed to derive turn info client-side.
  ///
  /// Single PostgREST query embedding:
  /// - `participants!inner(player_index)` — inner-joined and filtered to
  ///   the current user's row, so `player_index` is this user's slot in
  ///   that game.
  /// - `observations(pending_players, turn_deadline)` — narrowed to the
  ///   latest frame (observations are append-only); empty embed for
  ///   waiting/ready games (no observation row exists yet).
  ///
  /// Callers compute "is my turn" as
  /// `entry.pendingPlayers?.contains(entry.myPlayerIndex)`.
  Future<
    List<
      ({
        Game game,
        int myPlayerIndex,
        List<int>? pendingPlayers,
        DateTime? turnDeadline,
      })
    >
  >
  getActiveGameEntries() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await dbGuard(
      () => _client
          .from('games')
          .select(
            '*, participants!inner(user_id, player_index), '
            'observations(pending_players, turn_deadline)',
          )
          .eq('participants.user_id', userId)
          .inFilter('status', ['waiting', 'ready', 'active'])
          .order('version', referencedTable: 'observations', ascending: false)
          .limit(1, referencedTable: 'observations')
          .order('updated_at', ascending: false),
    );

    return response.map((j) {
      // The .eq('participants.user_id', userId) filter both (a) drives the
      // !inner outer selectivity (only games I'm in) and (b) narrows the
      // embedded array to my row. firstWhere makes that intent explicit
      // instead of relying on the narrowed array's ordering.
      final participant = (j['participants'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((p) => p['user_id'] == userId);
      final myPlayerIndex = participant['player_index'] as int;

      final observations = j['observations'] as List;
      final pendingPlayers = observations.isEmpty
          ? null
          : ((observations.first as Map<String, dynamic>)['pending_players']
                    as List)
                .cast<int>();
      final deadlineStr = observations.isEmpty
          ? null
          : (observations.first as Map<String, dynamic>)['turn_deadline']
                as String?;

      return (
        game: Game.fromJson(j),
        myPlayerIndex: myPlayerIndex,
        pendingPlayers: pendingPlayers,
        turnDeadline: deadlineStr != null ? DateTime.parse(deadlineStr) : null,
      );
    }).toList();
  }
}
