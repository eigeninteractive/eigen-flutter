import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_flutter/core/errors/error_messages.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_flutter/core/updates/required_update_button.dart';

import 'package:eigen_flutter/features/game/providers/game_frame_provider.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';
import 'package:eigen_flutter/features/game/providers/replay_controller.dart';
import 'package:eigen_api/eigen_api.dart';

/// Steps through a finished game's frame history, one observation at a time.
///
/// Renders through the same [GameRules.buildContent] path as the live game
/// screen, but feeds it a historical [GameFrame] chosen by a cursor instead of
/// the live stream, and never submits actions. Stepping forward one frame keeps
/// the underlying version consecutive so the game animates the transition;
/// scrubbing or stepping back snaps.
///
/// Serves both a participant reviewing their own game and a non-participant
/// replaying a public one; the difference is only which projection the
/// `game/replay` route returned, which this screen does not need to know.
class ReplayScreen extends ConsumerWidget {
  const ReplayScreen({super.key, required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final framesAsync = ref.watch(replayFramesProvider(gameId: gameId));

    return Scaffold(
      appBar: AppBar(title: const Text('Replay')),
      body: SafeArea(
        child: framesAsync.when(
          data: (frames) => frames.isEmpty
              ? const _ReplayMessage('This game has no frames to replay.')
              : _ReplayBody(gameId: gameId, frames: frames),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ReplayMessage(humanize(e)),
        ),
      ),
    );
  }
}

/// The board + controls, shown once the frame history has loaded.
class _ReplayBody extends ConsumerWidget {
  const _ReplayBody({required this.gameId, required this.frames});

  final String gameId;
  final List<Frame> frames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frameCount = frames.length;
    if (frames.any(
      (frame) => frame.type == FrameTypeEnum.unknownDefaultOpenApi,
    )) {
      return const _ReplayMessage(
        'This replay uses features from a newer version of the app.',
        showUpdate: true,
      );
    }
    final configAsync = ref.watch(gameConfigProvider(gameId: gameId));
    if (configAsync.error is UnsupportedGameSchemaException) {
      return const _ReplayMessage(
        'This game was created by a newer version of the app.',
        showUpdate: true,
      );
    }

    final config = configAsync.value;
    final rules = ref.watch(gameRulesProvider(gameId: gameId)).value;
    final playersAsync = ref.watch(gamePlayersProvider(gameId: gameId));
    final index = ref.watch(
      replayCursorProvider(gameId: gameId, frameCount: frameCount),
    );
    final frame = ref.watch(
      replayFrameAtProvider(gameId: gameId, index: index),
    );

    if (config == null ||
        rules == null ||
        frame == null ||
        frame.observation == null ||
        !playersAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    // The outcome (and any win chrome the game derives from it) belongs to the
    // final position, so it is only handed over on the last frame.
    final isLastFrame = index == frameCount - 1;
    final outcomes = isLastFrame
        ? ref
                  .watch(gameOutcomesProvider(gameId: gameId))
                  .whenOrNull(data: (o) => o) ??
              const <Outcome>[]
        : const <Outcome>[];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: rules.buildContent(
              GameContentContext(
                config: config,
                frame: frame,
                // Finished for every frame so the game keeps input inert; a
                // live status would re-enable the board on the actor's turn.
                gameStatus: GameStatus.finished,
                outcomes: outcomes,
                actionPending: false,
                onAction: (_) async => ActionSubmitResult.rejected,
                onInvalidAction: () {},
                playersContext: playersAsync.value!,
                isReplay: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _ReplayControls(gameId: gameId, index: index, frameCount: frameCount),
        ],
      ),
    );
  }
}

/// Prev/next stepping, a scrubber, and the current move label.
class _ReplayControls extends ConsumerWidget {
  const _ReplayControls({
    required this.gameId,
    required this.index,
    required this.frameCount,
  });

  final String gameId;
  final int index;
  final int frameCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final cursor = ref.read(
      replayCursorProvider(gameId: gameId, frameCount: frameCount).notifier,
    );
    final lastMove = frameCount - 1;
    final label = index == 0 ? 'Start' : 'Move $index of $lastMove';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: textTheme.labelLarge),
        Row(
          children: [
            IconButton(
              onPressed: index > 0 ? cursor.previous : null,
              icon: const Icon(Icons.skip_previous),
              tooltip: 'Previous move',
            ),
            Expanded(
              child: frameCount > 1
                  ? Slider(
                      value: index.toDouble(),
                      max: lastMove.toDouble(),
                      divisions: lastMove,
                      label: label,
                      onChanged: (v) => cursor.jumpTo(v.round()),
                    )
                  : const SizedBox.shrink(),
            ),
            IconButton(
              onPressed: index < lastMove ? cursor.next : null,
              icon: const Icon(Icons.skip_next),
              tooltip: 'Next move',
            ),
          ],
        ),
      ],
    );
  }
}

/// Centered message for the empty / error / unsupported states.
class _ReplayMessage extends StatelessWidget {
  const _ReplayMessage(this.text, {this.showUpdate = false});

  final String text;
  final bool showUpdate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (showUpdate) ...[
              const SizedBox(height: 24),
              const RequiredUpdateButton(),
            ],
          ],
        ),
      ),
    );
  }
}
