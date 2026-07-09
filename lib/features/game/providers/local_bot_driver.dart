import 'dart:async';
import 'dart:isolate';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:eigen_engine/core/game/participant_type.dart';
import 'package:eigen_engine/features/game/providers/game_frame_provider.dart';
import 'package:eigen_engine/features/game/providers/game_providers.dart';

part 'local_bot_driver.g.dart';

/// In-memory cache of local bots' committed per-(game, seat) state.
///
/// Survives screen navigation within an app session, so returning to a game does
/// not reset a bot's brain (its search tree / belief) — the per-seat driver is
/// screen-scoped and would otherwise re-seed from scratch via `createState`.
/// Cleared on app restart; durable resume would need disk persistence plus a
/// per-bot state codec.
/// Bounded to the most-recently-used [LocalBotStateCache._maxEntries] seats so a
/// long session of solo games cannot grow memory without limit.
@Riverpod(keepAlive: true)
LocalBotStateCache localBotStateCache(Ref ref) => LocalBotStateCache();

/// Backing store for [localBotStateCache] — pure storage (not reactive), read on
/// mount and written on each accepted move.
class LocalBotStateCache {
  static const _maxEntries = 16;
  final _states = <(String, int), Object?>{};

  Object? read(String gameId, int seatIndex) => _states[(gameId, seatIndex)];

  void write(String gameId, int seatIndex, Object? state) {
    final key = (gameId, seatIndex);
    _states.remove(key); // re-insert to mark most-recently-used
    _states[key] = state;
    if (_states.length > _maxEntries) {
      _states.remove(_states.keys.first); // evict least-recently-used
    }
  }
}

/// Supervises local bots in a solo game by keeping one [LocalBotSeatDriver]
/// alive per local-bot seat.
///
/// Watch it for the game screen's lifetime — its state is `void`, so it never
/// rebuilds the screen; it exists only to react. It evaluates the **solo gate
/// once** (exactly one human — a local bot is sound only when there is no other
/// human to cheat against) and, for every bot seat whose `username` matches a
/// shipped `GameRules.localBots` implementation (the game's own version unit),
/// watches that seat's driver.
/// Server-bot seats (no matching local impl) are skipped — their webhook drives
/// them.
@riverpod
class LocalBotDriver extends _$LocalBotDriver {
  @override
  void build({required String gameId}) {
    // The game's own version unit owns its local bots; rebuilds once resolved.
    final rules = ref.watch(gameRulesProvider(gameId: gameId)).value;
    if (rules == null || rules.localBots.isEmpty) return;

    final players = ref.watch(gamePlayersProvider(gameId: gameId)).value;
    if (players == null) return;

    final humanCount = players.players.values
        .where((p) => p.type == ParticipantType.human)
        .length;
    if (humanCount != 1) return;

    for (final entry in players.players.entries) {
      final seat = entry.value;
      if (seat.type != ParticipantType.bot) continue;
      final hasLocalImpl = rules.localBots.any(
        (b) => b.username == seat.info.username,
      );
      if (!hasLocalImpl) continue;
      ref.watch(
        localBotSeatDriverProvider(gameId: gameId, seatIndex: entry.key),
      );
    }
  }
}

/// Drives a single local-bot seat: each new observation where the seat is
/// pending spawns a fresh compute; the bot's pure `chooseAction` runs in an
/// **ephemeral isolate** (`Isolate.run`) so it never blocks a UI frame.
///
/// The seat's committed [TState] (held erased) lives here, on the main isolate —
/// so a superseded compute owns nothing: a newer observation just spawns a fresh
/// compute, and the stale one is dropped because it was computed on an
/// **older game version** than the latest the stream has seen. State is committed
/// **only when its action is accepted** by the server. The server re-checks
/// seat/version/pending under lock, so a stale or duplicated submit is rejected
/// and swallowed — this driver is an optimisation of "who computes", never a
/// trust boundary.
@riverpod
class LocalBotSeatDriver extends _$LocalBotSeatDriver {
  Object? _committed;

  @override
  void build({required String gameId, required int seatIndex}) {
    // Resume the bot's brain across screen navigation (within the app session).
    _committed = ref.read(localBotStateCacheProvider).read(gameId, seatIndex);

    // A single trigger: each observation where this seat is pending. `_spawn`
    // awaits its own prerequisites (engine, players), so there is no need to also
    // listen for *those* resolving — which is what keeps exactly one compute per
    // game version (no same-version duplicates from a startup kick storm).
    // `fireImmediately` covers an already settled game (e.g. revisited), where a
    // plain `listen` would wait for a change that may never come (it is already
    // the bot's turn).
    ref.listen(gameObservationProvider(gameId: gameId), (_, next) {
      final obs = next.value;
      if (obs == null || !obs.pendingPlayers.contains(seatIndex)) return;
      unawaited(_spawn(gameId, seatIndex));
    }, fireImmediately: true);
  }

  Future<void> _spawn(String gameId, int seatIndex) async {
    try {
      // Await prerequisites instead of bail-and-retry: the config future may
      // still be resolving on the first turn, and this lets one observation
      // trigger suffice (players is already resolved — the supervisor gated on
      // it — so its await returns immediately).
      final rules = await ref.read(gameRulesProvider(gameId: gameId).future);
      final gameConfig = await ref.read(
        gameConfigProvider(gameId: gameId).future,
      );
      final players = await ref.read(
        gamePlayersProvider(gameId: gameId).future,
      );
      if (!ref.mounted) return;

      final seat = players.players[seatIndex];
      if (seat == null || seat.type != ParticipantType.bot) return;
      final bot = rules.localBots
          .where((b) => b.username == seat.info.username)
          .firstOrNull;
      if (bot == null) return;

      // Bot capability (botConfig) comes from the cached catalog, keyed by
      // bot id.
      final catalog = await ref.read(botCatalogByIdProvider.future);
      if (!ref.mounted) return;
      final botConfig =
          catalog[seat.info.id]?.config ?? const <String, dynamic>{};

      _committed ??= bot.createState(
        rules: rules,
        gameConfig: gameConfig,
        seatIndex: seatIndex,
        botConfig: botConfig,
      );

      final repo = ref.read(gameRepositoryProvider);
      final obs = await repo.getLocalBotObservation(
        gameId: gameId,
        playerIndex: seatIndex,
      );
      if (!ref.mounted) return;
      // Still the bot's turn, and not already overtaken by a newer version?
      if (obs == null || !obs.pendingPlayers.contains(seatIndex)) return;
      if (_superseded(gameId, obs.version)) return;

      final parsed = rules.parseObservation(obs.data);

      // Run the pure compute off the UI thread. Capture only sendable locals
      // (never `this`): the bot, rules unit, configs, parsed observation and
      // committed state.
      final committed = _committed;
      final result = await Isolate.run(
        () => bot.chooseAction(
          rules: rules,
          gameConfig: gameConfig,
          observation: parsed,
          seatIndex: seatIndex,
          state: committed,
        ),
      );
      // A newer version arrived while computing → this action is stale; drop it
      // (and its state). The orphaned isolate finishes on its own and is GC'd.
      if (!ref.mounted || _superseded(gameId, obs.version)) return;

      await repo.submitLocalBotAction(
        gameId: gameId,
        playerIndex: seatIndex,
        actionData: rules.serializeAction(result.action),
        expectedVersion: obs.version,
      );
      // The submit was accepted (a version conflict would have thrown), and it
      // advanced the version itself — so commit unconditionally and cache it for
      // cross-navigation resume.
      if (!ref.mounted) return;
      _committed = result.state;
      ref.read(localBotStateCacheProvider).write(gameId, seatIndex, _committed);
    } catch (_) {
      // Expected races (turn advanced / version moved / deadline expired); the
      // next observation re-triggers if it is still the bot's turn.
    }
  }

  /// Whether a game version newer than [basisVersion] has already been observed —
  /// the action computed on [basisVersion] is then stale and must not be
  /// submitted. The version comes from the human's observation stream (the
  /// canonical game version, shared by every seat's row). Strictly-greater, not
  /// `!=`, because that stream is eventually-consistent and may momentarily lag
  /// the directly-fetched bot observation; the server's optimistic-version lock
  /// is the ultimate backstop regardless.
  bool _superseded(String gameId, int basisVersion) {
    final latest = ref
        .read(gameObservationProvider(gameId: gameId))
        .value
        ?.version;
    return latest != null && latest > basisVersion;
  }
}
