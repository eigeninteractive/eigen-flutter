part of 'game_screen.dart';

/// Shown for aborted games: cancelled by the host before starting, or
/// closed by the idle-cleanup job (which also aborts long-abandoned
/// untimed active games), so the copy stays neutral about timing.
class _AbortedContent extends StatelessWidget {
  const _AbortedContent();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cancel_outlined,
              size: 72,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'Game Cancelled',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This game was cancelled or closed due to inactivity.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a game uses a schema or wire value this build cannot present.
class _UpdateRequiredScroll extends StatelessWidget {
  const _UpdateRequiredScroll();

  @override
  Widget build(BuildContext context) => const CustomScrollView(
    physics: AlwaysScrollableScrollPhysics(),
    slivers: [
      SliverFillRemaining(
        hasScrollBody: false,
        child: _UpdateRequiredContent(),
      ),
    ],
  );
}

class _UpdateRequiredContent extends StatelessWidget {
  const _UpdateRequiredContent();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.system_update,
              size: 72,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'Update Required',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This game uses features from a newer version of the app. '
              'Please update to view it.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const RequiredUpdateButton(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [_ReconnectingBanner] when disconnected during any in-progress game
/// state (waiting, ready, or active).
///
/// Disconnected means device-level offline, the observation stream is in
/// [AsyncError], or the game stream itself is in [AsyncError], covering
/// transient socket blips where [isOfflineProvider] stays false. Uses
/// [AsyncValue.value] to read stale status during error states. Isolated as a
/// [ConsumerWidget] leaf so changes don't rebuild the entire game tree.
class _ReconnectingBannerSlot extends ConsumerWidget {
  const _ReconnectingBannerSlot({required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    final obsAsync = ref.watch(gameEventsProvider(gameId: gameId));
    final gameAsync = ref.watch(gameRosterProvider(gameId: gameId));
    final isDisconnected =
        isOffline || obsAsync is AsyncError || gameAsync is AsyncError;

    // Use .value to read stale status when stream is in AsyncError.
    final status = gameAsync.value?.status;
    final isInGame = switch (status) {
      GameStatus.waiting || GameStatus.ready || GameStatus.active => true,
      _ => false,
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: (isDisconnected && isInGame)
          ? const _ReconnectingBanner()
          : const SizedBox.shrink(),
    );
  }
}

/// Slim banner shown when connectivity drops during an active game.
class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return StatusBanner(
      leading: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
      label: 'Reconnecting…',
      backgroundColor: colorScheme.secondaryContainer,
      foregroundColor: colorScheme.onSecondaryContainer,
    );
  }
}

/// Generic error state with retry button.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: colorScheme.error),
          const SizedBox(height: 16),
          Text('Error: $error'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
