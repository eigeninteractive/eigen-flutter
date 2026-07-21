import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/engine_api_providers.dart';
import 'package:eigen_flutter/core/game/game_frame.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_flutter/core/game/timing_context.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'game_frame_provider.g.dart';

/// The [GameRules] version unit for a specific game, resolved once from the
/// game's immutable schema version.
///
/// This is the single version-dispatch point on the client: everything
/// downstream (engine, content, bots, seatability) consumes the resolved unit
/// and never branches on version.
@riverpod
Future<GameRules> gameRules(Ref ref, {required String gameId}) async {
  final module = ref.watch(currentGameModuleProvider);
  final summary = await ref.watch(gameSummaryProvider(gameId: gameId).future);
  final rules = module.versions[summary.schemaVersion];
  if (rules == null) {
    // Created by a newer build (or a retired version) - refuse rather than
    // mis-parse with the wrong generation of code.
    throw UnsupportedGameSchemaException(
      gameSchema: summary.schemaVersion,
      supportedSchema: module.latestSchemaVersion,
    );
  }
  return rules;
}

/// The parsed game config, produced once from the immutable config payload.
///
/// Config is set at creation and never mutated, so this is long-lived and
/// stands apart from the per-frame [GameFrame]. Erased to [Object] here - the
/// game casts to its concrete type.
@riverpod
Future<Object> gameConfig(Ref ref, {required String gameId}) async {
  final rules = await ref.watch(gameRulesProvider(gameId: gameId).future);
  final summary = await ref.watch(gameSummaryProvider(gameId: gameId).future);
  return rules.parseConfig(summary.config as Map<String, dynamic>) as Object;
}

/// Memoizes [GameRules.parseObservation] so it only runs when the raw payload
/// changes, not on every rebuild of [gameFrame].
@riverpod
Object? _parsedObservation(Ref ref, {required String gameId}) {
  final rules = ref.watch(gameRulesProvider(gameId: gameId)).value;
  final frame = ref.watch(gameFrameDataProvider(gameId: gameId));
  if (rules == null || frame == null) return null;
  return rules.parseObservation(frame.data as Map<String, dynamic>) as Object?;
}

/// The per-frame [GameFrame] the game renders from.
///
/// Null before the game is under way: frames only exist from v0 of an active
/// game onward, and there is nothing to project in the waiting room or after an
/// abort.
///
/// The parsed config is intentionally not part of this; consume it separately
/// via [gameConfig]. `pendingPlayers`, `version` and `timing` are available as
/// soon as the frame arrives, while `observation` stays null until the rules
/// unit has parsed it.
@riverpod
GameFrame? gameFrame(Ref ref, {required String gameId}) {
  final frame = ref.watch(gameFrameDataProvider(gameId: gameId));
  if (frame == null) return null;

  return GameFrame(
    observation: ref.watch(_parsedObservationProvider(gameId: gameId)),
    pendingPlayers: frame.pendingPlayers,
    version: frame.version,
    timing: TimingContext(
      clock: ref.watch(serverClockProvider),
      playerTimes: frame.playerTimes?.map((t) => t.toInt()).toList(),
      deadline: frame.deadline?.toInt(),
    ),
  );
}
