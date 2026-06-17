import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_engine/core/game/base_engine.dart';
import 'package:eigen_engine/core/game/game_frame.dart';
import 'package:eigen_engine/core/game/game_module.dart';
import 'package:eigen_engine/core/game/game_status.dart';
import 'package:eigen_engine/core/game/timing_context.dart';
import 'package:eigen_engine/features/game/providers/game_providers.dart';

part 'game_frame_provider.g.dart';

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

/// The engine for a specific game, created once from its immutable config.
///
/// Config is set at game creation and never mutated, so [ref.read] fetches
/// the first stream event rather than subscribing to future changes. The
/// engine is long-lived and stands apart from the per-event [GameFrame].
@riverpod
Future<BaseEngine> gameEngine(Ref ref, {required String gameId}) async {
  final module = ref.watch(currentGameModuleProvider);
  final game = await ref.read(gameStreamProvider(gameId: gameId).future);
  if (!module.supportsSchema(game.schemaVersion)) {
    // Created by a newer build — refuse rather than mis-parse with old code.
    throw UnsupportedGameSchemaException(
      gameSchema: game.schemaVersion,
      supportedSchema: module.schemaVersion,
    );
  }
  return module.createEngine(game.config, game.schemaVersion);
}

/// Memoizes [BaseEngine.parseObservation] so it only runs when the raw
/// observation payload changes — not on every [gameStreamProvider] event that
/// causes [gameFrame] to rebuild.
@riverpod
Object? _parsedObservation(Ref ref, {required String gameId}) {
  final engine = ref.watch(gameEngineProvider(gameId: gameId)).value;
  final obs = ref.watch(gameObservationProvider(gameId: gameId)).value;
  if (engine == null || obs == null) return null;
  return engine.parseObservation(obs.data);
}

/// Derives the per-event [GameFrame] from the observation stream.
///
/// Returns null for pre-game and terminal states ([GameStatus.waiting],
/// [GameStatus.ready], [GameStatus.aborted]) — the observation stream is only
/// meaningful once the game is [GameStatus.active] or [GameStatus.finished].
///
/// The engine is intentionally not part of the frame; consume it separately
/// via [gameEngineProvider]. The frame carries `pendingPlayers`, `version` and
/// `timing` from the raw observation as soon as it arrives; `observation` (the
/// parsed payload) stays null until the engine has parsed the first event.
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
