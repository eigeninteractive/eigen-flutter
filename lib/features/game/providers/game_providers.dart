import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:eigen_engine/core/game/game_module.dart';
import 'package:eigen_engine/core/game/game_player.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/core/game/players_context.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/game/data/game_repository.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
import 'package:eigen_engine/features/game/data/models/observation.dart';
import 'package:eigen_engine/shared/data/models/player_info.dart';
import 'package:eigen_engine/shared/providers/player_providers.dart';

part 'game_providers.g.dart';

/// Provider for GameRepository instance.
@Riverpod(keepAlive: true)
GameRepository gameRepository(Ref ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return GameRepository(supabase);
}

/// The active [GameModule].
///
/// Override in [ProviderScope] via:
/// ```dart
/// currentGameModuleProvider.overrideWithValue(const TicTacToeModule())
/// ```
/// Throws [UnimplementedError] at startup if no override is provided.
@Riverpod(keepAlive: true)
GameModule currentGameModule(Ref ref) => throw UnimplementedError(
  'No GameModule registered. '
  'Add currentGameModuleProvider.overrideWithValue(...) to ProviderScope.',
);

/// Provider for the current user's active games with the structural data
/// needed to derive turn info in the UI.
///
/// Fetches on first watch (auto-refresh on navigation) and on explicit
/// invalidation via [RefreshIndicator].
@riverpod
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
activeGames(Ref ref) async {
  final entries = await ref
      .watch(gameRepositoryProvider)
      .getActiveGameEntries();
  // "Your turn" first, then most recently updated. The secondary key is
  // explicit because List.sort is not guaranteed stable, so relying on the
  // SQL fetch order to survive the sort would be fragile.
  final sorted = entries.toList()
    ..sort((a, b) {
      final aMyTurn = a.pendingPlayers?.contains(a.myPlayerIndex) ?? false;
      final bMyTurn = b.pendingPlayers?.contains(b.myPlayerIndex) ?? false;
      if (aMyTurn != bMyTurn) return aMyTurn ? -1 : 1;
      return b.game.updatedAt.compareTo(a.game.updatedAt);
    });
  return sorted;
}

/// Provider for realtime game status updates.
///
/// Use this to detect when opponent joins or game status changes.
/// Automatically retries with exponential backoff on channel errors.
@riverpod
Stream<Game> gameStream(Ref ref, {required String gameId}) {
  final repository = ref.watch(gameRepositoryProvider);
  return repository.gameStream(gameId);
}

/// Fetches participants for a game, resolves each identity via the globally
/// cached [playerInfoCacheProvider], and returns the complete [PlayersContext]
/// with non-nullable player data.
///
/// Works for both human and bot participants — [playerInfoCacheProvider] queries
/// the unified `get_players` RPC covering both.
///
/// Auto-disposes when no screen watches it — a session can touch many games
/// (home cards, history navigation), and keeping every game's context alive
/// forever would grow unboundedly. Re-fetching is cheap: identities come from
/// the persisted [playerInfoCacheProvider]; only the participants query runs.
/// Invalidate when participants change (e.g. opponent joins, status changes).
@riverpod
Future<PlayersContext> gamePlayers(Ref ref, {required String gameId}) async {
  final repo = ref.watch(gameRepositoryProvider);
  final participants = await repo.getParticipants(gameId);
  final currentUserId = ref.watch(currentUserProvider)?.id;

  // Resolve all player identities in parallel via the cached provider.
  // userId and botId can both be null when a human account was deleted after
  // the game finished — fall back to a synthetic identity in that case.
  final entries = await Future.wait([
    for (final p in participants)
      () {
        final id = p.userId ?? p.botId;
        if (id != null) {
          return ref
              .watch(playerInfoCacheProvider(id: id).future)
              .then(
                (info) => MapEntry(
                  p.playerIndex,
                  GamePlayer(
                    playerIndex: p.playerIndex,
                    type: p.type,
                    info: info,
                  ),
                ),
              );
        }
        return Future.value(
          MapEntry(
            p.playerIndex,
            GamePlayer(
              playerIndex: p.playerIndex,
              type: p.type,
              info: _deletedPlayerInfo(gameId, p.playerIndex),
              isDeleted: true,
            ),
          ),
        );
      }(),
  ]);

  final myPlayerIndex =
      participants
          .where((p) => p.userId == currentUserId)
          .map((p) => p.playerIndex)
          .firstOrNull ??
      -1;

  return PlayersContext(
    players: Map.fromEntries(entries),
    myPlayerIndex: myPlayerIndex,
  );
}

/// Provider for observation stream (Realtime updates).
///
/// Automatically retries with exponential backoff on channel errors.
@riverpod
Stream<Observation> gameObservation(Ref ref, {required String gameId}) {
  final repository = ref.watch(gameRepositoryProvider);
  return repository.observationStream(gameId: gameId);
}

/// Synthetic identity for a participant whose account has been deleted.
///
/// Both [PlayerInfo.id] and [PlayerInfo.username] use a seat-scoped key so
/// different deleted players in the same game render distinctly.
PlayerInfo _deletedPlayerInfo(String gameId, int playerIndex) => PlayerInfo(
  id: 'deleted_${gameId}_$playerIndex',
  username: 'player_$playerIndex',
  displayName: 'Deleted User',
);

/// Joins a game by invite code and returns the game ID.
///
/// Auto-disposes once the join screen navigates away. The screen uses
/// [ref.listen] to react to the result rather than watching the value
/// directly, so navigation happens exactly once.
@riverpod
Future<String> joinByCode(Ref ref, {required String code}) =>
    ref.read(gameRepositoryProvider).joinGameByCode(
      code,
      clientSchemaVersion: ref.read(currentGameModuleProvider).schemaVersion,
    );

/// One-time fetch of game outcomes for a finished game.
///
/// Not a stream — outcomes are immutable once written by the server.
/// Returns an empty list while the game is still active (no outcome rows yet).
/// Invalidate this provider when [Game.status] transitions to [GameStatus.finished]
/// to trigger a fresh fetch.
@riverpod
Future<List<GameOutcome>> gameOutcomes(
  Ref ref, {
  required String gameId,
}) async {
  final repository = ref.watch(gameRepositoryProvider);
  return repository.getGameOutcomes(gameId);
}
