import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:riverpod_annotation/experimental/json_persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:eigen_engine/core/game/game_creation_spec.dart';
import 'package:eigen_engine/core/game/game_module.dart';
import 'package:eigen_engine/core/game/game_player.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/core/game/players_context.dart';
import 'package:eigen_engine/core/storage/storage_provider.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/game/data/game_repository.dart';
import 'package:eigen_engine/features/game/data/models/bot_info.dart';
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

/// The bot catalog for this deployment — the bot *capability* layer (is_local,
/// config, schema, rated-eligibility), used by the solo / "Add bot"
/// pickers and by the local-bot driver to resolve a seat's config.
///
/// `keepAlive`: the catalog is static reference data that changes rarely (bots are
/// added by hand in the dashboard), so it is fetched once and reused across the
/// session rather than re-fetched per screen. Invalidate to force a refresh.
///
/// `@JsonPersist()` caches it to SQLite so the pickers and the local-bot driver
/// resolve from cache (~5 ms) on cold start, before the network refresh lands
/// (stale-while-revalidate). The catalog is deployment-global public reference
/// data — like [PlayerInfoCache] it is **not** user-scoped and **not** cleared on
/// sign-out, so the auto-derived (no `key:`) global storage key is correct. Bump
/// [StorageOptions.destroyKey] if [BotInfo]'s persisted JSON shape changes.
@Riverpod(keepAlive: true)
@JsonPersist()
class AvailableBots extends _$AvailableBots {
  @override
  Future<List<BotInfo>> build() async {
    persist(
      ref.watch(storageProvider.future),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        // Bumped to '2': config is now required non-null (was nullable; server
        // rows cached with config:null in the old shape must be discarded).
        destroyKey: '2',
      ),
    );

    return ref.watch(gameRepositoryProvider).getBots();
  }
}

/// The bot catalog indexed by bot id, for O(1) capability lookups (e.g. the
/// local-bot driver resolving a seat's `config`). Derived from [availableBots].
@Riverpod(keepAlive: true)
Future<Map<String, BotInfo>> botCatalogById(Ref ref) async {
  final bots = await ref.watch(availableBotsProvider.future);
  return {for (final bot in bots) bot.id: bot};
}

/// Whether the solo-play entry should be offered for this deployment.
///
/// Solo play is available iff there is a playable (timing, bot-class) combination,
/// mirroring the `create_solo_game` partition (local ⇒ untimed, server ⇒ timed):
/// an **untimed** mode with a usable **local** bot, or a **timed** mode with a
/// usable **server** bot (servers are off-limits to guests). Gating the FAB on
/// this — not just "a local bot exists" — keeps a timed-only game from showing a
/// solo-play entry that would open a dead-end picker.
@riverpod
bool soloPlayAvailable(Ref ref) {
  final module = ref.watch(currentGameModuleProvider);
  final bots = ref.watch(availableBotsProvider).value ?? const [];
  final isGuest = ref.watch(isAnonymousProvider);

  final timing = module.creationSpec.timingConfigs.values;
  final hasUntimed = timing.any((c) => c is UntimedConfig);
  final hasTimed = timing.any((c) => c is! UntimedConfig);

  // Solo creation always targets the latest version, so bot usability is
  // evaluated against the latest rules unit.
  final hasUsableLocal = bots.any(
    (b) =>
        b.isLocal &&
        b.schemaVersion <= module.latestSchemaVersion &&
        module.latestRules.localBots.any((l) => l.username == b.username),
  );
  final hasUsableServer =
      !isGuest &&
      bots.any(
        (b) => !b.isLocal && b.schemaVersion <= module.latestSchemaVersion,
      );

  return (hasUntimed && hasUsableLocal) || (hasTimed && hasUsableServer);
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
/// the unified `app_players` RPC covering both.
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
Future<String> joinByCode(Ref ref, {required String code}) => ref
    .read(gameRepositoryProvider)
    .joinGameByCode(
      code,
      clientSchemaVersion: ref
          .read(currentGameModuleProvider)
          .latestSchemaVersion,
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
