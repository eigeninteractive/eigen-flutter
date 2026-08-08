part of 'game_screen.dart';

/// The active/finished game board and status.
///
/// Uses the game's [GameRules] version unit to render game-specific content,
/// keeping
/// [game_screen.dart] decoupled from any concrete game implementation.
///
/// Owns [gameFrameProvider] and [gamePlayersProvider] subscriptions so
/// observation updates rebuild only this widget, not the parent [_GameBody].
class _ActiveGameContent extends ConsumerWidget {
  const _ActiveGameContent({
    required this.game,
    required this.isSubmittingAction,
    required this.isForfeiting,
    required this.onAction,
    required this.onForfeit,
  });

  final GameSummary game;
  final bool isSubmittingAction;
  final bool isForfeiting;
  final Future<ActionSubmitResult> Function(Map<String, dynamic>, int) onAction;
  final Future<void> Function() onForfeit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // gameConfigProvider (data layer) is the single authority on whether this
    // build can load the game; here we only render its verdict. A game from
    // a newer build surfaces as UnsupportedGameSchemaException.
    final configAsync = ref.watch(gameConfigProvider(gameId: game.id));
    if (configAsync.error is UnsupportedGameSchemaException) {
      return const _UpdateRequiredContent();
    }

    final config = configAsync.value;
    // Resolved before the config (the config provider awaits it), so a
    // non-null config implies non-null rules.
    final rules = ref.watch(gameRulesProvider(gameId: game.id)).value;
    final gamePlayersAsync = ref.watch(gamePlayersProvider(gameId: game.id));

    // Essentials that don't depend on the live observation stream come first,
    // so a non-participant (who has no frame stream) can be handled before we
    // touch the frame.
    if (config == null || rules == null || !gamePlayersAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final gamePlayers = gamePlayersAsync.value!;

    // A non-participant has no observation rows and no per-seat frame stream,
    // so the live board can never render for them; it would spin forever.
    // Offer the replay (finished) or a wait message (active) instead.
    final mySeat = gamePlayers.mySeat;
    if (mySeat is! Seated) {
      return _NonParticipantContent(game: game);
    }
    final mySeatIndex = mySeat.index;

    final frame = ref.watch(gameFrameProvider(gameId: game.id));
    if (frame == null || frame.observation == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Outcomes are fetched once when the game finishes (invalidated by the
    // gameRosterProvider listener in _GameScreenState). Empty list for active
    // games, where no outcome rows exist yet.
    final outcomes =
        ref
            .watch(gameOutcomesProvider(gameId: game.id))
            .whenOrNull(data: (o) => o) ??
        const <Outcome>[];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (game.status == GameStatus.active)
            _TimingHeader(
              game: game,
              timing: frame.timing,
              pendingPlayers: frame.pendingPlayers,
              myPlayerIndex: mySeatIndex,
            ),
          Expanded(
            child: rules.buildContent(
              GameContentContext(
                config: config,
                frame: frame,
                gameStatus: game.status,
                outcomes: outcomes,
                actionPending: isSubmittingAction,
                onAction: (actionJson) => onAction(actionJson, frame.version),
                onInvalidAction: () =>
                    unawaited(HapticFeedback.selectionClick()),
                playersContext: gamePlayers,
              ),
            ),
          ),
          if (game.status == GameStatus.active)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ForfeitButton(
                isForfeiting: isForfeiting,
                onForfeit: onForfeit,
              ),
            ),
          if (game.status == GameStatus.finished)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => context.pushNamed(
                          'replay',
                          pathParameters: {'gameId': game.id},
                        ),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Watch replay'),
                      ),
                      _ShareReplayButton(game: game),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Shares a public finished game's replay link. Renders nothing for a private
/// game (a non-participant cannot replay it) or when no app host is configured.
class _ShareReplayButton extends ConsumerWidget {
  const _ShareReplayButton({required this.game});

  final GameSummary game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (game.access != GameAccess.public) return const SizedBox.shrink();
    final appHost = ref.watch(appConfigProvider).engine.appHost;
    final link = gameReplayLink(game.id, appHost: appHost);
    if (link == null) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () => SharePlus.instance.share(
        ShareParams(text: 'Replay this game: $link'),
      ),
      icon: const Icon(Icons.share),
      label: const Text('Share replay'),
    );
  }
}

/// Shown when a non-participant opens a public game.
///
/// A non-participant has no observation frames to render live, so a finished
/// game offers its replay and an in-progress game asks the viewer to come back.
class _NonParticipantContent extends StatelessWidget {
  const _NonParticipantContent({required this.game});

  final GameSummary game;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isFinished = game.status == GameStatus.finished;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFinished ? Icons.play_circle_outline : Icons.hourglass_top,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            isFinished
                ? 'This game has finished.'
                : 'Game in progress. The replay will be available when it '
                      'finishes.',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (isFinished)
            FilledButton.icon(
              onPressed: () => context.pushNamed(
                'replay',
                pathParameters: {'gameId': game.id},
              ),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Watch replay'),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.go('/home'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }
}

/// Selects the right timing widget based on the game's timing mode.
///
/// Budget mode → [BudgetClock] (all players' banks, live drain on active).
/// Per-action or hook-override deadline → [TurnCountdown] (single shared timer).
/// Untimed → empty.
class _TimingHeader extends StatelessWidget {
  const _TimingHeader({
    required this.game,
    required this.timing,
    required this.pendingPlayers,
    required this.myPlayerIndex,
  });

  final GameSummary game;
  final TimingContext timing;
  final List<int> pendingPlayers;
  final int myPlayerIndex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (game.budgetSeconds != null) {
      if (timing.playerTimes case final playerTimes?) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BudgetClock(
            playerTimes: playerTimes,
            deadline: timing.deadline,
            pendingPlayers: pendingPlayers,
            myPlayerIndex: myPlayerIndex,
          ),
        );
      }
    }

    if (timing.deadline case final deadline?) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            TurnCountdown(
              deadline: deadline,
              windowMillis: timing.windowMillis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Forfeit button that shows a confirmation dialog before calling [onForfeit].
class _ForfeitButton extends StatelessWidget {
  const _ForfeitButton({required this.isForfeiting, required this.onForfeit});

  final bool isForfeiting;
  final VoidCallback onForfeit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: colorScheme.error),
      onPressed: isForfeiting ? null : () => _confirm(context),
      icon: isForfeiting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.flag_outlined),
      label: const Text('Forfeit'),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Forfeit game?'),
        content: const Text(
          'Are you sure you want to forfeit this game? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Forfeit'),
          ),
        ],
      ),
    );
    if (confirmed == true) onForfeit();
  }
}

/// Outlined cancel button with loading spinner state.
class _CancelButton extends StatelessWidget {
  const _CancelButton({
    required this.isCancelling,
    required this.onCancel,
    required this.label,
  });

  final bool isCancelling;
  final VoidCallback onCancel;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: isCancelling ? null : onCancel,
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.error,
        side: BorderSide(color: colorScheme.error),
      ),
      icon: isCancelling
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cancel_outlined),
      label: Text(label),
    );
  }
}
