import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
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
/// All write operations use RPC functions. Clients read observations
/// via Realtime subscriptions.
class GameRepository {
  GameRepository(this._client);

  final SupabaseClient _client;

  /// Creates a new game via RPC.
  ///
  /// Returns the game ID.
  ///
  /// [turnSeconds] and [budgetSeconds] are mutually exclusive timing modes.
  /// Passing both throws on the server.
  Future<String> createGame({
    GameAccess access = GameAccess.public,
    int? turnSeconds,
    int? budgetSeconds,
    int? incrementSeconds,
    required int minPlayers,
    required int maxPlayers,
    Map<String, dynamic>? config,
    bool ratedPreference = true,
  }) async {
    final result = await _client.rpc(
      'create_game',
      params: {
        'p_access': access.name,
        'p_turn_seconds': ?turnSeconds,
        'p_budget_seconds': ?budgetSeconds,
        'p_increment_seconds': ?incrementSeconds,
        'p_min_players': minPlayers,
        'p_max_players': maxPlayers,
        'p_config': config,
        'p_rated_preference': ratedPreference,
      },
    );
    return result as String;
  }

  /// Joins a game via RPC.
  ///
  /// Returns the participant ID.
  Future<String> joinGame(String gameId) async {
    final result = await _client.rpc(
      'join_game',
      params: {'p_game_id': gameId},
    );
    return result as String;
  }

  /// Joins a game by short code via RPC.
  ///
  /// Returns the game ID.
  Future<String> joinGameByCode(String code) async {
    final result = await _client.rpc(
      'join_game_by_code',
      params: {'p_code': code},
    );
    return result as String;
  }

  /// Starts a game via RPC (host only).
  Future<void> startGame(String gameId) async {
    await _client.rpc('start_game', params: {'p_game_id': gameId});
  }

  /// Submits an action via RPC.
  ///
  /// Fire-and-forget: returns as soon as the server accepts the action.
  /// The client waits for the observation update via Realtime subscription
  /// to confirm the state change.
  ///
  /// On an optimistic-lock conflict the server raises a `Stale state` error,
  /// which the UI surfaces as a humanized "board updated — try again" message.
  Future<void> submitAction({
    required String gameId,
    required Map<String, dynamic> actionData,
    required int expectedVersion,
  }) async {
    await _client.rpc(
      'submit_action',
      params: {
        'p_game_id': gameId,
        'p_data': actionData,
        'p_expected_version': expectedVersion,
      },
    );
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
  /// Delegates to the [get_lobby_games] RPC, which filters full games via a
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
      _getJoinableGames('get_lobby_games', cursor);

  /// Gets friends-access games that are open for joining, including the
  /// current user's own rooms.
  Future<
    List<({Game game, List<Participant> participants, bool isParticipant})>
  >
  getFriendsGames({DateTime? cursor}) =>
      _getJoinableGames('get_friends_games', cursor);

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
    await _client.rpc('trigger_turn_expiry', params: {'p_game_id': gameId});
  }

  /// Leaves a waiting or ready game (non-creator participants only).
  ///
  /// The creator cannot leave — use [cancelGame] instead.
  Future<void> leaveGame(String gameId) async {
    await _client.rpc('leave_game', params: {'p_game_id': gameId});
  }

  /// Cancels a waiting game (creator only).
  Future<void> cancelGame(String gameId) async {
    await _client.rpc('cancel_game', params: {'p_game_id': gameId});
  }

  /// Forfeits an active game.
  ///
  /// Any participant may forfeit regardless of whose turn it is. No version
  /// check — forfeiting is an unconditional intent, and the server's row
  /// lock already serialises it against concurrent actions.
  Future<void> forfeitGame(String gameId) async {
    await _client.rpc('forfeit_game', params: {'p_game_id': gameId});
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

  /// Gets participants for a game.
  Future<List<Participant>> getParticipants(String gameId) async {
    final response = await _client
        .from('participants')
        .select()
        .eq('game_id', gameId)
        .order('player_index');

    return response.map((json) => Participant.fromJson(json)).toList();
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
