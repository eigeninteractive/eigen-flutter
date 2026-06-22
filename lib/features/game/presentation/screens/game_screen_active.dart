part of 'game_screen.dart';

/// The active/finished game board and status.
///
/// Uses [currentGameModuleProvider] to render game-specific content, keeping
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

  final Game game;
  final bool isSubmittingAction;
  final bool isForfeiting;
  final Future<void> Function(Map<String, dynamic>, int) onAction;
  final Future<void> Function() onForfeit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // gameEngineProvider (engine/data layer) is the single authority on whether
    // this build can load the game; here we only render its verdict. A game from
    // a newer build surfaces as UnsupportedGameSchemaException.
    final engineAsync = ref.watch(gameEngineProvider(gameId: game.id));
    if (engineAsync.error is UnsupportedGameSchemaException) {
      return const _UnsupportedSchemaContent();
    }

    final engine = engineAsync.value;
    final frame = ref.watch(gameFrameProvider(gameId: game.id));
    final gamePlayersAsync = ref.watch(gamePlayersProvider(gameId: game.id));

    if (engine == null ||
        frame == null ||
        frame.observation == null ||
        !gamePlayersAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final gamePlayers = gamePlayersAsync.value!;
    final module = ref.watch(currentGameModuleProvider);
    final myPlayerIndex = gamePlayers.myPlayerIndex;

    // Outcomes are fetched once when the game finishes (invalidated by the
    // gameStreamProvider listener in _GameScreenState). Empty list for active
    // games — no outcome rows exist yet.
    final outcomes =
        ref
            .watch(gameOutcomesProvider(gameId: game.id))
            .whenOrNull(data: (o) => o) ??
        const <GameOutcome>[];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (game.status == GameStatus.active)
            _TimingHeader(
              game: game,
              timing: frame.timing,
              pendingPlayers: frame.pendingPlayers,
              myPlayerIndex: myPlayerIndex,
            ),
          Expanded(
            child: module.buildContent(
              GameContentContext(
                engine: engine,
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
              child: OutlinedButton.icon(
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Home'),
              ),
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

  final Game game;
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
            turnStartedAt: timing.turnStartedAt,
            pendingPlayers: pendingPlayers,
            myPlayerIndex: myPlayerIndex,
          ),
        );
      }
    }

    if (timing.turnDeadline case final deadline?) {
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
              turnStartedAt: timing.turnStartedAt,
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
