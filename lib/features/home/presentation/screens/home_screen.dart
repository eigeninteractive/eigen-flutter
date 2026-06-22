import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:eigen_engine/core/game/participant_type.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
import 'package:eigen_engine/features/game/presentation/extensions/game_ui.dart';
import 'package:eigen_engine/features/game/presentation/widgets/turn_countdown.dart';
import 'package:eigen_engine/features/game/providers/game_providers.dart';
import 'package:eigen_engine/features/game/utils/game_timing.dart';
import 'package:eigen_engine/features/profile/providers/profile_providers.dart';
import 'package:eigen_engine/shared/widgets/overlapping_avatars.dart';

/// Home screen showing active games dashboard.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  DateTime _lastRefreshed = DateTime.now();

  Future<void> _onRefresh() async {
    ref.invalidate(activeGamesProvider);
    await ref.read(activeGamesProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final activeGamesAsync = ref.watch(activeGamesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // Track when the provider finishes loading so the "updated ago" label
    // resets after a pull-to-refresh or navigation-triggered reload.
    ref.listen(activeGamesProvider, (prev, next) {
      if (next.hasValue && (prev == null || prev.isLoading)) {
        setState(() => _lastRefreshed = DateTime.now());
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WelcomeHeader(),
        const SizedBox(height: 16),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: activeGamesAsync.when(
              skipLoadingOnReload: true,
              data: (entries) => entries.isEmpty
                  ? _EmptyState(
                      onBrowseLobby: () => context.go('/lobby'),
                      onJoinViaCode: () => _showJoinCodeDialog(context),
                    )
                  : _GamesList(
                      entries: entries,
                      lastRefreshed: _lastRefreshed,
                      onRefresh: _onRefresh,
                      onBrowseLobby: () => context.go('/lobby'),
                      onJoinViaCode: () => _showJoinCodeDialog(context),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    const Text('Error loading games'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => ref.invalidate(activeGamesProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showJoinCodeDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => const _JoinCodeDialog(),
    );
  }
}

/// Dialog prompting for a 6-character invite code.
///
/// Stateful so the [TextEditingController] is disposed with the dialog.
class _JoinCodeDialog extends StatefulWidget {
  const _JoinCodeDialog();

  @override
  State<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<_JoinCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _join() {
    final code = _controller.text.trim().toUpperCase();
    if (code.length != 6) return;
    // Capture the router before popping — this State's context is being
    // removed from the tree once the dialog closes.
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.pushNamed('join', pathParameters: {'code': code});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join Private Game'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          hintText: 'Enter 6-character code',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.characters,
        maxLength: 6,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _join, child: const Text('Join')),
      ],
    );
  }
}

/// Welcome header with user name greeting.
class _WelcomeHeader extends ConsumerWidget {
  const _WelcomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final profileAsync = ref.watch(currentUserProfileProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          profileAsync.when(
            data: (profile) => Text(
              'Welcome, @${profile.username}',
              style: textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            loading: () => _UsernameShimmer(
              baseColor: colorScheme.surfaceContainerHighest,
              highlightColor: colorScheme.surfaceContainerHigh,
              height:
                  (textTheme.titleLarge?.fontSize ?? 22) *
                  (textTheme.titleLarge?.height ?? 1.3),
            ),
            error: (_, _) => Text(
              'Welcome, Stranger',
              style: textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ready to conquer?',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer skeleton sized to match the [titleLarge] greeting line.
class _UsernameShimmer extends StatelessWidget {
  const _UsernameShimmer({
    required this.baseColor,
    required this.highlightColor,
    required this.height,
  });

  final Color baseColor;
  final Color highlightColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: 180,
        height: height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

/// Empty state when no active games.
///
/// Uses [CustomScrollView] + [SliverFillRemaining] so the parent
/// [RefreshIndicator] can detect a pull gesture even when content is
/// shorter than the viewport — without hardcoding any heights.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onBrowseLobby, required this.onJoinViaCode});

  final VoidCallback onBrowseLobby;
  final VoidCallback onJoinViaCode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sports_esports_outlined,
                      size: 64,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'No Active Games',
                    style: textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Start a new game to begin playing!\n'
                    'Challenge friends or join public matches.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onBrowseLobby,
                        icon: const Icon(Icons.search),
                        label: const Text('Browse Lobby'),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        onPressed: onJoinViaCode,
                        icon: const Icon(Icons.login),
                        label: const Text('Join via Code'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// List of active games.
class _GamesList extends StatelessWidget {
  const _GamesList({
    required this.entries,
    required this.lastRefreshed,
    required this.onRefresh,
    required this.onBrowseLobby,
    required this.onJoinViaCode,
  });

  final List<
    ({
      Game game,
      int myPlayerIndex,
      List<int>? pendingPlayers,
      DateTime? turnDeadline,
    })
  >
  entries;
  final DateTime lastRefreshed;
  final VoidCallback onRefresh;
  final VoidCallback onBrowseLobby;
  final VoidCallback onJoinViaCode;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Games',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _UpdatedAgoLabel(refreshedAt: lastRefreshed),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh,
                tooltip: 'Refresh',
                iconSize: 20,
              ),
              IconButton(
                icon: const Icon(Icons.login),
                onPressed: onJoinViaCode,
                tooltip: 'Join via Code',
                iconSize: 20,
              ),
              TextButton.icon(
                onPressed: onBrowseLobby,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Lobby'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: entries.length,
            itemBuilder: (context, index) => _GameCard(entry: entries[index]),
          ),
        ),
      ],
    );
  }
}

/// Card for a single game.
class _GameCard extends ConsumerWidget {
  const _GameCard({required this.entry});

  final ({
    Game game,
    int myPlayerIndex,
    List<int>? pendingPlayers,
    DateTime? turnDeadline,
  })
  entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final game = entry.game;

    // Null pendingPlayers = no observation yet (waiting/ready game).
    final isMyTurn = entry.pendingPlayers?.contains(entry.myPlayerIndex);
    final turnColor = isMyTurn == true
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    // Resolve player identities from the cached game players provider.
    final gamePlayersAsync = ref.watch(gamePlayersProvider(gameId: game.id));
    final gamePlayers =
        gamePlayersAsync.value?.players.values.toList() ?? const [];
    final avatars = [
      for (final gp in gamePlayers)
        (info: gp.info, isBot: gp.type == ParticipantType.bot),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () =>
            context.pushNamed('game', pathParameters: {'gameId': game.id}),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (avatars.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: OverlappingAvatars(players: avatars, radius: 18),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    color: game.status
                        .color(colorScheme)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    game.status.icon,
                    color: game.status.color(colorScheme),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Game #${game.id.substring(0, 8)}',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${game.status.name} • ${gameTimingLabel(game)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isMyTurn != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            isMyTurn ? '• Your turn' : '• Waiting',
                            style: textTheme.bodySmall?.copyWith(
                              color: turnColor,
                              fontWeight: isMyTurn
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          if (isMyTurn && entry.turnDeadline != null) ...[
                            const SizedBox(width: 4),
                            TurnCountdown(deadline: entry.turnDeadline!),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live "Updated X ago" label that ticks every second.
///
/// Resets automatically when the parent passes a new [refreshedAt].
class _UpdatedAgoLabel extends StatefulWidget {
  const _UpdatedAgoLabel({required this.refreshedAt});

  final DateTime refreshedAt;

  @override
  State<_UpdatedAgoLabel> createState() => _UpdatedAgoLabelState();
}

class _UpdatedAgoLabelState extends State<_UpdatedAgoLabel> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _label {
    final elapsed = DateTime.now().difference(widget.refreshedAt);
    if (elapsed.inSeconds < 10) return 'just now';
    if (elapsed.inSeconds < 60) return '${elapsed.inSeconds}s ago';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    return '${elapsed.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isStale =
        DateTime.now().difference(widget.refreshedAt).inSeconds > 30;
    return Text(
      'Updated $_label',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: isStale ? colorScheme.error : colorScheme.onSurfaceVariant,
      ),
    );
  }
}
