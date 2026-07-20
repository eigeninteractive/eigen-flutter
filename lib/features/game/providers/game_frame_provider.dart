import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_flutter/core/game/game_frame.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_flutter/core/game/game_status.dart';
import 'package:eigen_flutter/core/game/timing_context.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';

part 'game_frame_provider.g.dart';

/// The [GameRules] version unit for a specific game, resolved once from the
/// game's immutable `games.schema_version`.
///
/// This is the single version-dispatch point on the client: everything
/// downstream (engine, content, bots, seatability) consumes the resolved unit
/// and never branches on version.
@riverpod
Future<GameRules> gameRules(Ref ref, {required String gameId}) async {
  final module = ref.watch(currentGameModuleProvider);
  final game = await ref.read(gameStreamProvider(gameId: gameId).future);
  final rules = module.versions[game.schemaVersion];
  if (rules == null) {
    // Created by a newer build (or a retired version) — refuse rather than
    // mis-parse with the wrong generation of code.
    throw UnsupportedGameSchemaException(
      gameSchema: game.schemaVersion,
      supportedSchema: module.latestSchemaVersion,
    );
  }
  return rules;
}

/// The parsed game config, produced once from the immutable `games.config`
/// via the version unit's [GameRules.parseConfig].
///
/// Config is set at game creation and never mutated, so [ref.read] fetches
/// the first stream event rather than subscribing to future changes. The
/// parsed config is long-lived and stands apart from the per-event
/// [GameFrame]; it reaches the game as [GameContentContext.config]. Erased to
/// [Object] here — the game casts to its concrete type.
@riverpod
Future<Object> gameConfig(Ref ref, {required String gameId}) async {
  final rules = await ref.watch(gameRulesProvider(gameId: gameId).future);
  final game = await ref.read(gameStreamProvider(gameId: gameId).future);
  return rules.parseConfig(game.config) as Object;
}

/// Memoizes [GameRules.parseObservation] so it only runs when the raw
/// observation payload changes — not on every [gameStreamProvider] event that
/// causes [gameFrame] to rebuild.
@riverpod
Object? _parsedObservation(Ref ref, {required String gameId}) {
  final rules = ref.watch(gameRulesProvider(gameId: gameId)).value;
  final obs = ref.watch(gameObservationProvider(gameId: gameId)).value;
  if (rules == null || obs == null) return null;
  return rules.parseObservation(obs.data) as Object?;
}

/// Derives the per-event [GameFrame] from the observation stream.
///
/// Returns null for pre-game and terminal states ([GameStatus.waiting],
/// [GameStatus.ready], [GameStatus.aborted]) — the observation stream is only
/// meaningful once the game is [GameStatus.active] or [GameStatus.finished].
///
/// The parsed config is intentionally not part of the frame; consume it
/// separately via [gameConfigProvider]. The frame carries `pendingPlayers`,
/// `version` and `timing` from the raw observation as soon as it arrives;
/// `observation` (the parsed payload) stays null until the rules unit has
/// parsed the first event.
@riverpod
GameFrame? gameFrame(Ref ref, {required String gameId}) {
  final status = ref.watch(gameStreamProvider(gameId: gameId)).value?.status;

  if (status == null ||
      status == GameStatus.waiting ||
      status == GameStatus.ready ||
      status == GameStatus.aborted) {
    return null;
  }

  final obs = ref.watch(gameObservationProvider(gameId: gameId)).value;
  return GameFrame(
    observation: ref.watch(_parsedObservationProvider(gameId: gameId)),
    pendingPlayers: obs?.pendingPlayers ?? [],
    version: obs?.version ?? 0,
    timing: TimingContext(
      playerTimes: obs?.playerTimes,
      turnStartedAt: obs?.turnStartedAt,
      turnDeadline: obs?.turnDeadline,
    ),
  );
}
