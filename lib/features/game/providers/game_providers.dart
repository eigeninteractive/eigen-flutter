import 'dart:async';

import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/analytics/analytics_provider.dart';
import 'package:eigen_flutter/core/api/engine_api_providers.dart';
import 'package:eigen_flutter/core/api/game_socket.dart';
import 'package:eigen_flutter/core/game/game_creation_spec.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_flutter/core/game/game_player.dart';
import 'package:eigen_flutter/core/game/my_seat.dart';
import 'package:eigen_flutter/core/game/players_context.dart';
import 'package:eigen_flutter/core/storage/storage_provider.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:eigen_flutter/features/game/data/game_repository.dart';
import 'package:eigen_flutter/shared/providers/player_providers.dart';
import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:riverpod_annotation/experimental/json_persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'game_providers.g.dart';

/// Provider for GameRepository instance.
@Riverpod(keepAlive: true)
GameRepository gameRepository(Ref ref) {
  return GameRepository(
    ref.watch(gamesApiProvider),
    ref.watch(botsApiProvider),
    ref.watch(playersApiProvider),
    ref.watch(gameSocketProvider),
  );
}

/// The active [GameModule].
///
/// [runEngineApp] registers the game module for normal apps. Widget tests that
/// construct their own `ProviderScope` can override it directly:
/// ```dart
/// currentGameModuleProvider.overrideWithValue(const TicTacToeModule())
/// ```
/// Throws [UnimplementedError] at startup if no override is provided.
@Riverpod(keepAlive: true)
GameModule currentGameModule(Ref ref) => throw UnimplementedError(
  'No GameModule registered. '
  'Add currentGameModuleProvider.overrideWithValue(...) to ProviderScope.',
);

/// The bot catalog for this deployment - the pickers' source of truth.
///
/// `keepAlive`: static reference data that changes rarely (bots are registered
/// by an operator), so it is fetched once and reused for the session.
///
/// `@JsonPersist()` caches it locally so the pickers resolve from cache on cold
/// start, before the network refresh lands. The catalog is
/// deployment-global public reference data - like [PlayerInfoCache] it is not
/// user-scoped and not cleared on sign-out, so the auto-derived global storage
/// key is correct.
@Riverpod(keepAlive: true)
@JsonPersist()
class AvailableBots extends _$AvailableBots {
  @override
  Future<List<Bot>> build() async {
    persist(
      ref.watch(storageProvider.future),
      options: const StorageOptions(
        cacheTime: StorageCacheTime(Duration(days: 7)),
        // Bumped to '3': bots are now the generated Bot, which dropped the
        // is_local flag along with client-driven bots.
        destroyKey: '3',
      ),
    );

    return ref.watch(gameRepositoryProvider).getBots();
  }
}

/// The bot catalog indexed by id, for O(1) capability lookups.
@Riverpod(keepAlive: true)
Future<Map<String, Bot>> botCatalogById(Ref ref) async {
  final bots = await ref.watch(availableBotsProvider.future);
  return {for (final bot in bots) bot.id: bot};
}

/// Whether the solo-play entry should be offered for this deployment.
///
/// Two conditions, both enforced server-side too - this only avoids offering an
/// entry that would fail:
///
/// 1. **A bot this build's rules can play.** Solo creation always targets the
///    latest version, so usability is judged against the latest unit.
/// 2. **A timed mode.** A *server-seated* bot requires one: dispatch is
///    single-attempt, so if a bot's turn is never delivered the only thing that
///    resolves the game is the turn deadline firing the server's alarm. Untimed
///    means no deadline, no alarm, and a game wedged forever - the server
///    refuses it on the seating path.
///
/// Guests are deliberately *not* gated out: solo-vs-bot is a guest's first-run
/// experience, and the server accepts it - the game simply comes out unrated,
/// since rating requires a registered account.
///
/// Gating on both - rather than just "a bot exists" - keeps an untimed-only
/// deployment from showing a solo entry that opens a dead-end picker.
///
/// The timing condition is deliberately tied to *server* seating rather than to
/// bots in general, because the deferred offline-solo path will not share it: a
/// client-driven bot has no dispatch to fail, so an on-device game can be
/// untimed. When that lands, this becomes a choice between two solo modes
/// (untimed on-device, timed server-seated) rather than a single gate, and the
/// partition it needs is already the one expressed here.
@riverpod
bool soloPlayAvailable(Ref ref) {
  final module = ref.watch(currentGameModuleProvider);
  final bots = ref.watch(availableBotsProvider).value ?? const [];

  final hasTimedMode = module.creationSpec.timingConfigs.values.any(
    (c) => c is! UntimedConfig,
  );
  final hasUsableBot = bots.any(
    (b) => b.schemaVersion <= module.latestSchemaVersion,
  );
  return hasTimedMode && hasUsableBot;
}

/// The caller's games, "your turn" first then most recently updated.
///
/// One request: the summary already carries the roster, the pending set and
/// the deadline, so nothing has to be derived from a second read.
@riverpod
Future<List<GameSummary>> activeGames(Ref ref) async {
  final games = await ref.watch(gameRepositoryProvider).getMyGames();
  final myUserId = ref.watch(currentUserIdProvider);

  bool isMyTurn(GameSummary game) {
    final seat = game.participants
        .where((p) => p.userId == myUserId)
        .map((p) => p.playerIndex)
        .firstOrNull;
    return seat != null && (game.pendingPlayers?.contains(seat) ?? false);
  }

  // The secondary key is explicit because List.sort is not stable, so relying
  // on the server's order to survive the sort would be fragile.
  return games.toList()..sort((a, b) {
    final aMine = isMyTurn(a);
    if (aMine != isMyTurn(b)) return aMine ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  });
}

/// One game's metadata: schema version, config, timing, access.
///
/// A plain read rather than a stream. These fields are fixed at creation and
/// never change, so streaming them would be re-delivering constants; what does
/// change - status and roster - arrives on [gameEvents] instead.
@riverpod
Future<GameSummary> gameSummary(Ref ref, {required String gameId}) {
  return ref.watch(gameRepositoryProvider).getGame(gameId);
}

/// Whether the current wire payload contains gameplay semantics this build
/// cannot safely interpret.
typedef GameWireCompatibility = ({
  bool unknownStatus,
  bool unknownSeatType,
  bool unknownFrameType,
  bool unknownAccess,
});

extension GameWireCompatibilityX on GameWireCompatibility {
  /// Whether gameplay must stop until the client updates.
  bool get requiresUpdate =>
      unknownStatus || unknownSeatType || unknownFrameType;
}

/// Compatibility verdict across the initial summary and live game payloads.
///
/// Status, seat type, and frame type drive gameplay behavior, so guessing would
/// be unsafe. Metadata-only unknowns such as access remain usable with
/// conservative UI.
@riverpod
GameWireCompatibility gameWireCompatibility(Ref ref, {required String gameId}) {
  final summary = ref.watch(gameSummaryProvider(gameId: gameId)).value;
  final roster = ref.watch(gameRosterProvider(gameId: gameId)).value;
  final frame = ref.watch(gameFrameDataProvider(gameId: gameId));
  return evaluateGameWireCompatibility(
    summaryStatus: summary?.status,
    summarySeats: summary?.participants,
    access: summary?.access,
    rosterStatus: roster?.status,
    rosterSeats: roster?.players,
    frameType: frame?.type,
  );
}

/// Computes compatibility without requiring a provider container.
GameWireCompatibility evaluateGameWireCompatibility({
  GameStatus? summaryStatus,
  Iterable<Seat>? summarySeats,
  GameAccess? access,
  GameStatus? rosterStatus,
  Iterable<Seat>? rosterSeats,
  FrameTypeEnum? frameType,
}) {
  return (
    unknownStatus:
        summaryStatus == GameStatus.unknownDefaultOpenApi ||
        rosterStatus == GameStatus.unknownDefaultOpenApi,
    unknownSeatType:
        _hasUnknownSeatType(summarySeats) || _hasUnknownSeatType(rosterSeats),
    unknownFrameType: frameType == FrameTypeEnum.unknownDefaultOpenApi,
    unknownAccess: access == GameAccess.unknownDefaultOpenApi,
  );
}

bool _hasUnknownSeatType(Iterable<Seat>? seats) =>
    seats?.any((seat) => seat.type == SeatTypeEnum.unknownDefaultOpenApi) ??
    false;

/// The game's live feed: roster snapshots pre-game, then ordered frames.
///
/// One socket serves the whole game, so this is the single subscription a game
/// screen needs. Riverpod's automatic retry covers a failure to establish it;
/// drops after that are handled inside the socket, which reconnects and
/// resyncs without tearing down this stream.
@riverpod
Stream<GameSocketEvent> gameEvents(Ref ref, {required String gameId}) {
  return ref.watch(gameRepositoryProvider).events(gameId);
}

/// The newest roster seen for a game, seeded from the summary.
///
/// The socket delivers a snapshot on open and on every roster change while the
/// game is in the waiting room, but sends none once play starts - so the
/// summary provides the starting value and later snapshots replace it.
@riverpod
Future<Roster> gameRoster(Ref ref, {required String gameId}) async {
  final summary = await ref.watch(gameSummaryProvider(gameId: gameId).future);
  final event = ref.watch(gameEventsProvider(gameId: gameId)).value;
  if (event is GameSocketRoster) return event.roster;
  return Roster(
    type: RosterTypeEnum.roster,
    status: summary.status,
    players: summary.participants,
  );
}

/// The newest frame seen for a game, or null before the first one arrives.
@riverpod
Frame? gameFrameData(Ref ref, {required String gameId}) {
  final event = ref.watch(gameEventsProvider(gameId: gameId)).value;
  return event is GameSocketFrame ? event.frame : null;
}

/// The game's seats with their identities resolved, plus which one is mine.
///
/// Seats come from the live roster rather than a separate fetch, so this
/// re-derives as players join and leave. Identities come from the persisted
/// player cache, which covers humans and bots alike.
@riverpod
Future<PlayersContext> gamePlayers(Ref ref, {required String gameId}) async {
  final roster = await ref.watch(gameRosterProvider(gameId: gameId).future);
  final currentUserId = ref.watch(currentUserIdProvider);

  final entries = await Future.wait([
    for (final seat in roster.players)
      _resolveSeat(ref, gameId: gameId, seat: seat),
  ]);

  final mySeat = roster.players
      .where((p) => p.userId == currentUserId)
      .map((p) => p.playerIndex)
      .firstOrNull;

  return PlayersContext(
    players: Map.fromEntries(entries),
    mySeat: mySeat == null ? const Viewer() : Seated(mySeat),
  );
}

/// Resolves one seat's identity, substituting a placeholder for a purged
/// account.
///
/// Both ids are null when a human deleted their account after the game
/// finished. The seat still has to render, so it gets a synthetic identity -
/// marked [GamePlayer.isDeleted] so callers know not to feed its id back into
/// an identity lookup or a profile sheet.
Future<MapEntry<int, GamePlayer>> _resolveSeat(
  Ref ref, {
  required String gameId,
  required Seat seat,
}) async {
  final id = seat.userId ?? seat.botId;

  if (id == null) {
    return MapEntry(
      seat.playerIndex,
      GamePlayer(
        playerIndex: seat.playerIndex,
        type: seat.type,
        info: _deletedPlayer(gameId, seat.playerIndex),
        isDeleted: true,
      ),
    );
  }

  final info = await ref.watch(playerInfoCacheProvider(id: id).future);
  return MapEntry(
    seat.playerIndex,
    GamePlayer(playerIndex: seat.playerIndex, type: seat.type, info: info),
  );
}

/// Synthetic identity for a seat whose account has been deleted.
///
/// The id and username are seat-scoped so two deleted players in one game
/// render distinctly, and so neither collides with a real id.
Player _deletedPlayer(String gameId, int playerIndex) => Player(
  id: 'deleted_${gameId}_$playerIndex',
  username: 'player_$playerIndex',
  displayName: 'Deleted User',
  avatarUrl: null,
  isAnonymous: false,
);

/// Joins a game by invite code, returning the game's id and its roster.
///
/// Auto-disposes once the join screen navigates away. The screen uses
/// [ref.listen] to react to the result rather than watching the value
/// directly, so navigation happens exactly once.
@riverpod
Future<Joined> joinByCode(Ref ref, {required String code}) => ref
    .read(gameRepositoryProvider)
    .joinGameByCode(
      code,
      clientSchemaVersion: ref
          .read(currentGameModuleProvider)
          .latestSchemaVersion,
    );

/// A finished game's outcomes.
///
/// Immutable once written, and already on the summary - so this is a
/// projection rather than a fetch. Empty while the game is still running.
@riverpod
Future<List<Outcome>> gameOutcomes(Ref ref, {required String gameId}) async {
  final summary = await ref.watch(gameSummaryProvider(gameId: gameId).future);
  final outcomes = summary.outcomes ?? const [];
  if (outcomes.any(
    (outcome) => outcome.result == OutcomeResultEnum.unknownDefaultOpenApi,
  )) {
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .wireEnumFallback(enumType: 'OutcomeResult', surface: 'game'),
    );
  }
  return outcomes;
}

/// A player's most recent finished public games, for the replay list on their
/// profile.
///
/// Works for any player, human or bot. Public and finished only, so it never
/// exposes a game that was not already replayable by anyone holding its id.
@riverpod
Future<List<GameSummary>> playerPublicFinishedGames(
  Ref ref, {
  required String playerId,
}) {
  return ref.watch(gameRepositoryProvider).getPlayerGames(playerId);
}
