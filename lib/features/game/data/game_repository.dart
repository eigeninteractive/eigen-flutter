import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/features/game/data/models/bot_info.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
import 'package:eigen_engine/features/game/data/models/observation.dart';
import 'package:eigen_engine/features/game/data/models/participant.dart';
import 'package:eigen_engine/features/rating/data/models/rating_change.dart';

/// Number of games fetched per lobby page.
const lobbyPageSize = 50;

/// Number of games fetched per history page.
const historyPageSize = 30;

/// Repository for game operations.
///
/// GameEngine operations (start, action, forfeit, expiry, local-bot moves) go
/// through the `game` Edge Function, which runs the TypeScript gameEngine and
/// commits via gated RPCs. Lobby/discovery/bot-catalog operations and reads stay
/// on PostgREST RPCs. Clients read observations via Realtime subscriptions.
class GameRepository {
  GameRepository(this._client);

  final SupabaseClient _client;

  /// Invokes an `engine` Edge Function game route, normalising errors so
  /// [humanize] still recognises the server's message (e.g. "Stale state").
  ///
  /// The function returns `{ "error": "<message>" }` with a non-2xx status on
  /// failure; supabase throws [FunctionException] carrying that body in
  /// [FunctionException.details]. We rethrow an [Exception] whose message is the
  /// server text so the existing humanizer matches unchanged.
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
      throw Exception(message);
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
  /// from the rating rules (the Dart twin of `GameEngine.ratingPool`, plus the
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
  /// ([GameModule.schemaVersion]); the server refuses to seat the caller in a
  /// game whose `schema_version` exceeds it, so the client never becomes a
  /// participant in a game it cannot render.
  ///
  /// Returns the participant ID.
  Future<String> joinGame(
    String gameId, {
    required int clientSchemaVersion,
  }) async {
    final result = await _client.rpc(
      'app_join_game',
      params: {
        'p_game_id': gameId,
        'p_client_schema_version': clientSchemaVersion,
      },
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
    final result = await _client.rpc(
      'app_join_game_by_code',
      params: {'p_code': code, 'p_client_schema_version': clientSchemaVersion},
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
  /// Fire-and-forget: returns as soon as the server accepts the action.
  /// The client waits for the observation update via Realtime subscription
  /// to confirm the state change.
  ///
  /// On an optimistic-lock conflict the server raises a `Stale state` error,
  /// which the UI surfaces as a humanized "the game updated — try again" message.
  Future<void> submitAction({
    required String gameId,
    required Map<String, dynamic> actionData,
    required int expectedVersion,
  }) async {
    await _invokeEngine('action', {
      'game_id': gameId,
      'data': actionData,
      'expected_version': expectedVersion,
    });
  }

  /// Fetches the outcomes for a completed game.
  ///
  /// Returns one [GameOutcome] per participant. Empty for games that are not
  /// yet finished. Call this once when [Game.status] transitions to finished.
  Future<List<GameOutcome>> getGameOutcomes(String gameId) async {
    final response = await _client
        .from('game_outcomes')
        .select()
        .eq('game_id', gameId)
        .order('player_index');
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
    final response = await _client.rpc(
      rpcName,
      params: {
        if (cursor != null) 'p_cursor': cursor.toIso8601String(),
        'p_limit': lobbyPageSize,
      },
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
    await _client.rpc('app_leave_game', params: {'p_game_id': gameId});
  }

  /// Cancels a waiting game (creator only).
  Future<void> cancelGame(String gameId) async {
    await _client.rpc('app_cancel_game', params: {'p_game_id': gameId});
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

    final response = await query
        .order('finished_at', ascending: false)
        .limit(historyPageSize);

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
    final result = await _client.rpc('app_bots');
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(BotInfo.fromJson)
        .toList();
  }

  /// Creates a solo game: the caller plus [botIds] (local and/or server, in seat
  /// order), unrated. The EF gates each bot's config seatability
  /// ([GameModule.botSeatable]) in TS, then `engine_create_solo_game` creates +
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
  /// gates config seatability ([GameModule.botSeatable]) before seating.
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

  /// Fetches a bot seat's [Observation] for local play, server-gated to the sole
  /// human of a solo game. The RPC returns `SETOF observations` — the same shape
  /// as a human's own observation — so this reads it with [maybeSingle] exactly
  /// like [getObservation]: null when no row exists yet. The `(game_id,
  /// player_index)` PK bounds the set to one row, so [maybeSingle] raising on
  /// multiple rows can only mean that invariant was violated — a loud failure is
  /// the right outcome there rather than silently picking an arbitrary seat's
  /// hidden view.
  Future<Observation?> getLocalBotObservation({
    required String gameId,
    required int playerIndex,
  }) async {
    final response = await _client
        .rpc(
          'app_local_bot_observation',
          params: {'p_game_id': gameId, 'p_player_index': playerIndex},
        )
        .maybeSingle();

    if (response == null) return null;
    return Observation.fromJson(response);
  }

  /// Gets the participants of a game — ephemeral, per-game data (seat + identity
  /// ids + type). RLS restricts rows to games the caller can see. A bot seat's
  /// reference data (display via [PlayerInfo], capability/config via the cached
  /// bot catalog) is resolved separately by id, not joined here.
  Future<List<Participant>> getParticipants(String gameId) async {
    final response = await _client
        .from('participants')
        .select()
        .eq('game_id', gameId)
        .order('player_index');
    return response.map(Participant.fromJson).toList();
  }

  /// Gets the current user's observation for a game.
  ///
  /// RLS restricts results to the authenticated user's row, so no explicit
  /// user_id filter is needed.
  Future<Observation?> getObservation(String gameId) async {
    final response = await _client
        .from('observations')
        .select()
        .eq('game_id', gameId)
        .maybeSingle();

    if (response == null) return null;
    return Observation.fromJson(response);
  }

  /// Subscribes to observation updates for a game via the Realtime channel API.
  ///
  /// Emits the current observation immediately on subscribe (REST fetch), then
  /// emits on every subsequent change. Re-fetches current state on every
  /// re-subscribe so no updates are missed during a reconnect. RLS restricts
  /// results to the authenticated user's own row.
  Stream<Observation> observationStream({required String gameId}) {
    final userId = _client.auth.currentUser?.id;
    // Signed out (e.g. session expired mid-game) — emit nothing rather than
    // crash; the auth redirect tears the screen down momentarily.
    if (userId == null) return const Stream.empty();
    return _channelStream(
      channelName: 'observations:$gameId:$userId',
      table: 'observations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'game_id',
        value: gameId,
      ),
      fetchCurrent: () async {
        final data = await _client
            .from('observations')
            .select()
            .eq('game_id', gameId)
            .maybeSingle();
        return data == null ? null : Observation.fromJson(data);
      },
      fromRecord: Observation.fromJson,
    );
  }

  /// Subscribes to game metadata updates via the Realtime channel API.
  ///
  /// Useful for detecting when opponents join (status changes) or game ends.
  /// Emits the current game immediately on subscribe and on every reconnect.
  Stream<Game> gameStream(String gameId) {
    return _channelStream(
      channelName: 'games:$gameId',
      table: 'games',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: gameId,
      ),
      fetchCurrent: () async {
        final data = await _client
            .from('games')
            .select()
            .eq('id', gameId)
            .single();
        return Game.fromJson(data);
      },
      fromRecord: Game.fromJson,
    );
  }

  /// Opens a Realtime channel for [table] rows matching [filter] and wraps it
  /// in a [StreamController].
  ///
  /// On every [RealtimeSubscribeStatus.subscribed] event (initial connect and
  /// every reconnect), [fetchCurrent] is called via REST to guarantee the
  /// stream reflects the latest row even if a change was missed while
  /// disconnected. Change payloads are decoded via [fromRecord] and emitted
  /// directly without a REST round-trip.
  ///
  /// [channelError] and [timedOut] propagate as stream errors so Riverpod's
  /// retry mechanism can schedule a reconnect with exponential backoff.
  /// [closed] is a no-op — Supabase's [RealtimeClient] automatically rejoins
  /// all channels after a WebSocket drop, which fires [subscribed] again.
  ///
  /// The channel is unsubscribed when the stream subscription is cancelled
  /// (e.g. when the Riverpod provider is disposed or invalidated). The channel
  /// removes itself from [RealtimeClient.channels] via its own close callback.
  Stream<T> _channelStream<T>({
    required String channelName,
    required String table,
    required PostgresChangeFilter filter,
    required Future<T?> Function() fetchCurrent,
    required T Function(Map<String, dynamic>) fromRecord,
  }) {
    late RealtimeChannel channel;
    late StreamController<T> controller;

    void doFetch() {
      fetchCurrent().then(
        (v) {
          if (v != null && !controller.isClosed) controller.add(v);
        },
        onError: (Object e) {
          if (!controller.isClosed) controller.addError(e);
        },
      );
    }

    controller = StreamController<T>(onCancel: () => channel.unsubscribe());

    channel = _client.channel(channelName)
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: filter,
        callback: (payload) {
          if (payload.newRecord.isNotEmpty && !controller.isClosed) {
            controller.add(fromRecord(payload.newRecord));
          }
        },
      )
      ..subscribe((status, error) {
        switch (status) {
          case RealtimeSubscribeStatus.subscribed:
            doFetch();
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
  /// - `observations(pending_players)` — empty embed for waiting/ready
  ///   games (no observation row exists yet).
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

    final response = await _client
        .from('games')
        .select(
          '*, participants!inner(user_id, player_index), '
          'observations(pending_players, turn_deadline)',
        )
        .eq('participants.user_id', userId)
        .inFilter('status', ['waiting', 'ready', 'active'])
        .order('updated_at', ascending: false);

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
