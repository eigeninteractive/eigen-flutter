import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_flutter/core/api/engine_api_providers.dart';
import 'package:eigen_flutter/core/game/game_frame.dart';
import 'package:eigen_flutter/core/game/timing_context.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';
import 'package:eigen_flutter/features/game/providers/game_frame_provider.dart';

part 'replay_controller.g.dart';

/// The full ordered frame history of a finished game, fetched once.
///
/// A finished game's history is immutable, so this is fetched a single time and
/// cached for the life of the replay screen. A participant receives their own
/// seat's projection; a non-participant replaying a public game receives the
/// observer projection - the shape is identical either way, so the replay UI
/// does not branch on it.
///
/// The same range endpoint backs live gap recovery; replay is just the whole
/// range rather than a missing slice of it.
@riverpod
Future<List<Frame>> replayFrames(Ref ref, {required String gameId}) {
  return ref.watch(gameRepositoryProvider).getFrames(gameId);
}

/// The current position within a game's replay, as an index into
/// [replayFramesProvider].
///
/// Starts at 0 (the initial frame) so the replay plays forward from the
/// beginning. [frameCount] is passed by the screen once the frames have
/// loaded, so stepping and scrubbing clamp to the valid range without the
/// controller re-reading the async list. Stepping forward one frame keeps the
/// underlying `version` consecutive, which is what lets the game animate the
/// transition; jumping or stepping back is non-consecutive and snaps.
@riverpod
class ReplayCursor extends _$ReplayCursor {
  @override
  int build({required String gameId, required int frameCount}) => 0;

  /// Advances to the next frame, if any. A single forward step animates.
  void next() {
    if (state < frameCount - 1) state = state + 1;
  }

  /// Returns to the previous frame, if any. Snaps (non-consecutive version).
  void previous() {
    if (state > 0) state = state - 1;
  }

  /// Jumps to an arbitrary frame (e.g. a scrubber drag), clamped to range.
  void jumpTo(int index) {
    if (frameCount == 0) return;
    state = index.clamp(0, frameCount - 1);
  }
}

/// The [GameFrame] for a single replay frame index.
///
/// Memoized per `(gameId, index)`: [GameRules.parseObservation] runs once per
/// frame no matter how often the user steps back and forth across it. Timing is
/// always empty — a replay has no live clocks. Returns null until the frames
/// and the version unit have both loaded, or for an out-of-range index.
@riverpod
GameFrame? replayFrameAt(
  Ref ref, {
  required String gameId,
  required int index,
}) {
  final rules = ref.watch(gameRulesProvider(gameId: gameId)).value;
  final frames = ref.watch(replayFramesProvider(gameId: gameId)).value;
  if (rules == null || frames == null || index < 0 || index >= frames.length) {
    return null;
  }
  final frame = frames[index];
  return GameFrame(
    observation: rules.parseObservation(frame.data as Map<String, dynamic>),
    pendingPlayers: frame.pendingPlayers,
    version: frame.version,
    // A replay has no live clocks: the deadlines these frames carried have
    // long passed, and re-rendering them as countdowns would be nonsense.
    timing: TimingContext(clock: ref.watch(serverClockProvider)),
  );
}
