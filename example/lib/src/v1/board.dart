/// The in-game screen for RPS v1: everything [RpsRulesV1.buildContent]
/// renders.
///
/// The framework has already done the work that is not game-specific by the
/// time this builds: auth, the socket, gap recovery, the countdown, the
/// pending/finished chrome, and the JSON parsing. What is left is this file,
/// and it is the shape most games end up with: read the observation, draw it,
/// submit an action, reconcile.
library;

import 'package:eigen_flutter/eigen_flutter.dart';
import 'package:flutter/material.dart';

import 'models.dart';

/// The board: score, the previous round's reveal, and three buttons.
class RpsBoard extends StatefulWidget {
  const RpsBoard({super.key, required this.context, required this.rules});

  /// Everything infra hands a game for this frame.
  final GameContentContext context;

  /// The rules unit that built this widget, so legality is asked of the one
  /// place a shared fixture can hold to account rather than re-decided here.
  /// Taking it as a parameter (instead of importing `rules.dart`) is also what
  /// keeps rendering and rules from importing each other.
  final GameRules<RpsV1Observation, RpsV1Action, RpsV1Config> rules;

  @override
  State<RpsBoard> createState() => _RpsBoardState();
}

class _RpsBoardState extends State<RpsBoard> {
  /// The move tapped on this device but not yet reflected in a frame.
  ///
  /// This is the game's whole optimism story, and it deliberately lives in
  /// widget state rather than in a predicted observation: RPS cannot predict
  /// its next observation at all (see [RpsRulesV1.previewAction]), but it can
  /// always know what *this* player just did. Showing that immediately is what
  /// makes the tap feel instant across a round trip.
  RpsV1Move? _submitting;

  @override
  void didUpdateWidget(RpsBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new frame is the authority; drop the local guess so the two can never
    // disagree on screen. Frames arrive in version order with no gaps, so this
    // fires exactly once per commit.
    if (widget.context.frame.version != oldWidget.context.frame.version) {
      _submitting = null;
    }
  }

  Future<void> _throw(RpsV1Move move) async {
    final ctx = widget.context;
    final seat = ctx.mySeat.indexOrNull;
    final obs = ctx.frame.observation! as RpsV1Observation;
    final config = ctx.config as RpsV1Config;
    final action = RpsV1Action(move: move);

    // Ask the rules unit, not this widget. The same check runs server-side in
    // the TS `applyAction`, and keeping the client's copy in the rules unit is
    // what lets a fixture prove the two agree.
    final legal =
        seat != null &&
        widget.rules.isValidAction(
          obs: obs,
          pending: ctx.frame.pendingPlayers,
          data: action,
          playerIndex: seat,
          config: config,
        );
    if (!legal) {
      ctx.onInvalidAction();
      return;
    }

    setState(() => _submitting = move);
    final result = await ctx.onAction(action.toJson());
    if (!mounted) return;
    // `committed` needs no handling: the confirming frame is guaranteed to be
    // the next one this seat receives, and `didUpdateWidget` clears the guess
    // when it lands. The other two mean no frame is coming for this tap, so
    // the buttons have to come back; infra has already shown the player why.
    if (result != ActionSubmitResult.committed) {
      setState(() => _submitting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.context;
    final obs = ctx.frame.observation! as RpsV1Observation;
    final config = ctx.config as RpsV1Config;
    final seat = ctx.mySeat.indexOrNull;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Scoreboard(
            observation: obs,
            config: config,
            players: ctx.playersContext,
          ),
          const SizedBox(height: 32),
          Expanded(
            child: _Reveal(round: obs.lastRound, mySeat: seat),
          ),
          const SizedBox(height: 16),
          _StatusLine(
            observation: obs,
            gameStatus: ctx.gameStatus,
            outcomes: ctx.outcomes,
            mySeat: seat,
            submitting: _submitting,
          ),
          const SizedBox(height: 16),
          _MoveButtons(
            // Disabled for every reason a throw would be rejected, so an
            // illegal tap is normally impossible and `onInvalidAction` is the
            // backstop rather than the mechanism.
            enabled:
                seat != null &&
                !ctx.isReplay &&
                !ctx.actionPending &&
                _submitting == null &&
                ctx.frame.pendingPlayers.contains(seat) &&
                !obs.committedBy(seat),
            chosen: _submitting ?? obs.yourMove,
            onThrow: _throw,
          ),
        ],
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.observation,
    required this.config,
    required this.players,
  });

  final RpsV1Observation observation;
  final RpsV1Config config;
  final PlayersContext players;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Round ${observation.round} · first to ${config.targetWins}',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var seat = 0; seat < observation.wins.length; seat++)
              _SeatScore(
                player: players[seat],
                wins: observation.wins[seat],
                isMe: players.mySeat.indexOrNull == seat,
              ),
          ],
        ),
      ],
    );
  }
}

class _SeatScore extends StatelessWidget {
  const _SeatScore({
    required this.player,
    required this.wins,
    required this.isMe,
  });

  final GamePlayer player;
  final int wins;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        PlayerAvatar(
          avatarUrl: player.info.avatarUrl,
          isBot: player.type == SeatTypeEnum.bot,
          radius: 24,
          showBorder: isMe,
        ),
        const SizedBox(height: 6),
        Text(player.info.displayName, style: theme.textTheme.bodyMedium),
        Text('$wins', style: theme.textTheme.headlineMedium),
      ],
    );
  }
}

/// The previous round's throws. Null before the first round resolves.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.round, required this.mySeat});

  final RpsV1Round? round;
  final int? mySeat;

  @override
  Widget build(BuildContext context) {
    final last = round;
    if (last == null) {
      return const Center(child: Text('Throw when ready.'));
    }
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var seat = 0; seat < last.moves.length; seat++) ...[
                if (seat > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('vs', style: theme.textTheme.labelLarge),
                  ),
                Text(
                  _glyph(last.moves[seat]),
                  style: const TextStyle(fontSize: 56),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(switch (last.winner) {
            null => 'Drawn round',
            final winner when winner == mySeat => 'You won the round',
            _ => 'You lost the round',
          }, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.observation,
    required this.gameStatus,
    required this.outcomes,
    required this.mySeat,
    required this.submitting,
  });

  final RpsV1Observation observation;
  final GameStatus gameStatus;
  final List<Outcome> outcomes;
  final int? mySeat;
  final RpsV1Move? submitting;

  @override
  Widget build(BuildContext context) {
    final seat = mySeat;
    final text = switch (gameStatus) {
      GameStatus.finished => _finishedText(seat),
      // Committed but no reveal yet: the opponent's pending status is masked,
      // so "waiting" is genuinely all this seat knows.
      _
          when submitting != null ||
              (seat != null && observation.committedBy(seat)) =>
        'Waiting for your opponent…',
      _ => 'Your throw.',
    };
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }

  String _finishedText(int? seat) {
    if (seat == null) return 'Match over.';
    OutcomeResultEnum? mine;
    for (final outcome in outcomes) {
      if (outcome.playerIndex == seat) mine = outcome.result;
    }
    return switch (mine) {
      OutcomeResultEnum.win => 'You won the match.',
      OutcomeResultEnum.loss => 'You lost the match.',
      OutcomeResultEnum.draw => 'The match was drawn.',
      _ => 'Match over.',
    };
  }
}

class _MoveButtons extends StatelessWidget {
  const _MoveButtons({
    required this.enabled,
    required this.chosen,
    required this.onThrow,
  });

  final bool enabled;
  final RpsV1Move? chosen;
  final ValueChanged<RpsV1Move> onThrow;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final move in RpsV1Move.values)
          _MoveButton(
            move: move,
            selected: move == chosen,
            onPressed: enabled ? () => onThrow(move) : null,
          ),
      ],
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.move,
    required this.selected,
    required this.onPressed,
  });

  final RpsV1Move move;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: move.name,
      child: IconButton.filled(
        onPressed: onPressed,
        iconSize: 40,
        style: IconButton.styleFrom(
          backgroundColor: selected ? scheme.primary : scheme.surfaceContainer,
          padding: const EdgeInsets.all(16),
        ),
        icon: Text(_glyph(move), style: const TextStyle(fontSize: 32)),
      ),
    );
  }
}

String _glyph(RpsV1Move move) => switch (move) {
  RpsV1Move.rock => '✊',
  RpsV1Move.paper => '✋',
  RpsV1Move.scissors => '✌️',
};
