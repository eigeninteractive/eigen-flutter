import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:eigen_engine/core/errors/error_messages.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/game/data/game_repository.dart';
import 'package:eigen_engine/core/game/participant_type.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
import 'package:eigen_engine/features/game/data/models/participant.dart';
import 'package:eigen_engine/features/game/providers/game_providers.dart';
import 'package:eigen_engine/features/game/utils/game_timing.dart';
import 'package:eigen_engine/features/game/presentation/widgets/new_game_dialog.dart';
import 'package:eigen_engine/shared/providers/player_providers.dart';
import 'package:eigen_engine/shared/widgets/empty_state_view.dart';
import 'package:eigen_engine/shared/widgets/overlapping_avatars.dart';

/// Screen for browsing and joining public games.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

typedef _LobbyEntry = ({
  Game game,
  List<Participant> participants,
  bool isParticipant,
});

enum _LobbyMode { public, friends }

class _LobbyScreenState extends ConsumerState<LobbyScreen>
    with SingleTickerProviderStateMixin {
  // Guests cannot have friends. The Friends tab stays visible but disabled
  // (greyed, with a locked sign-in panel as its content) so guests still see
  // the feature exists — and app_friends_games is never called for them.
  // Decided once at init: a guest→permanent conversion is a full auth-state
  // change that re-navigates into a fresh lobby.
  late final bool _isAnonymous;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _isAnonymous = ref.read(isAnonymousProvider);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final disabledColor = colorScheme.onSurface.withValues(alpha: 0.38);

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.public), text: 'Public'),
            Tab(
              icon: Icon(
                Icons.people,
                color: _isAnonymous ? disabledColor : null,
              ),
              child: Text(
                'Friends',
                style: _isAnonymous ? TextStyle(color: disabledColor) : null,
              ),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              const _LobbyTabContent(mode: _LobbyMode.public),
              if (_isAnonymous)
                const _FriendsLockedView()
              else
                const _LobbyTabContent(mode: _LobbyMode.friends),
            ],
          ),
        ),
      ],
    );
  }
}

/// Locked content shown to guests in place of the friends lobby. The Friends
/// tab is visible but non-functional until they create an account — mirroring
/// the disabled "Sign up to play rated" treatment on rated game cards.
class _FriendsLockedView extends StatelessWidget {
  const _FriendsLockedView();

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.lock_outline,
      title: 'Friends games',
      message: 'Sign in to add friends and play private games with them.',
      cta: 'Sign in',
      tonalCta: true,
      onCta: () => context.goNamed('settings'),
    );
  }
}

class _LobbyTabContent extends ConsumerStatefulWidget {
  const _LobbyTabContent({required this.mode});

  final _LobbyMode mode;

  @override
  ConsumerState<_LobbyTabContent> createState() => _LobbyTabContentState();
}

class _LobbyTabContentState extends ConsumerState<_LobbyTabContent>
    with AutomaticKeepAliveClientMixin {
  late final PagingController<String, _LobbyEntry> _pagingController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pagingController = PagingController<String, _LobbyEntry>(
      getNextPageKey: (state) {
        final pages = state.pages;
        if (pages == null || pages.isEmpty) return '';
        final lastPage = pages.last;
        if (lastPage.length < lobbyPageSize) return null;
        return lastPage.last.game.createdAt.toIso8601String();
      },
      fetchPage: (key) {
        final cursor = key.isEmpty ? null : DateTime.parse(key);
        if (widget.mode == _LobbyMode.public) {
          return ref.read(gameRepositoryProvider).getLobbyGames(cursor: cursor);
        } else {
          return ref
              .read(gameRepositoryProvider)
              .getFriendsGames(cursor: cursor);
        }
      },
    );
    _pagingController.addListener(_onPagingError);
  }

  void _onPagingError() {
    if (!mounted) return;
    if (_pagingController.value.status == PagingStatus.subsequentPageError) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              humanize(_pagingController.value.error ?? 'Unknown error'),
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _pagingController.fetchNextPage,
            ),
          ),
        );
    }
  }

  @override
  void dispose() {
    _pagingController
      ..removeListener(_onPagingError)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async => _pagingController.refresh(),
      child: PagingListener(
        controller: _pagingController,
        builder: (context, state, fetchNextPage) =>
            PagedListView<String, _LobbyEntry>(
              state: state,
              fetchNextPage: fetchNextPage,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              builderDelegate: PagedChildBuilderDelegate<_LobbyEntry>(
                animateTransitions: true,
                itemBuilder: (context, item, index) => _GameCard(
                  key: ValueKey(item.game.id),
                  game: item.game,
                  participants: item.participants,
                  isParticipant: item.isParticipant,
                  onCancelled: _pagingController.refresh,
                  onJoined: _pagingController.refresh,
                ),
                noItemsFoundIndicatorBuilder: (_) => EmptyStateView(
                  icon: Icons.sports_esports_outlined,
                  title: 'No open games right now',
                  message: switch (widget.mode) {
                    _LobbyMode.friends =>
                      'None of your friends have an open game.',
                    _LobbyMode.public => 'Be the first to start one.',
                  },
                  cta: 'Create Game',
                  onCta: () => showDialog(
                    context: context,
                    useSafeArea: true,
                    builder: (_) => const NewGameDialog(),
                  ),
                ),
                firstPageErrorIndicatorBuilder: (_) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(humanize(state.error ?? 'Unknown error')),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _pagingController.refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ),
    );
  }
}

class _GameCard extends ConsumerStatefulWidget {
  const _GameCard({
    super.key,
    required this.game,
    required this.participants,
    required this.isParticipant,
    required this.onCancelled,
    required this.onJoined,
  });

  final Game game;
  final List<Participant> participants;
  final bool isParticipant;
  final VoidCallback onCancelled;
  final VoidCallback onJoined;

  @override
  ConsumerState<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends ConsumerState<_GameCard> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final isOwner = widget.game.createdBy == currentUser?.id;
    final canNavigate = isOwner || widget.isParticipant;
    // A game created by a newer build cannot be rendered by this client; refuse
    // to join (and thus seat) it. The server enforces the same check, but
    // disabling the button gives immediate feedback instead of a failed tap.
    final supported = ref
        .watch(currentGameModuleProvider)
        .supportsSchema(widget.game.schemaVersion);
    // Guests play unrated only. The server rejects a guest joining a rated game;
    // disabling the button (rather than hiding the game) gives immediate
    // feedback and nudges them to sign up, mirroring the unsupported case.
    final ratedBlockedForGuest =
        widget.game.rated && ref.watch(isAnonymousProvider);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final playerCount = widget.participants.length;

    // Resolve participant PlayerInfo from the cached provider.
    final avatars = <AvatarEntry>[];
    for (final p in widget.participants) {
      final playerId = p.userId ?? p.botId;
      if (playerId == null) continue;
      final info = ref.watch(playerInfoCacheProvider(id: playerId));
      if (info.value case final value?) {
        avatars.add((info: value, isBot: p.type == ParticipantType.bot));
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: canNavigate
            ? () => context.pushNamed(
                'game',
                pathParameters: {'gameId': widget.game.id},
              )
            : null,
        leading: avatars.isNotEmpty
            ? OverlappingAvatars(players: avatars, radius: 18)
            : CircleAvatar(
                backgroundColor: isOwner
                    ? colorScheme.secondaryContainer
                    : colorScheme.primaryContainer,
                child: Icon(
                  gameTimingIcon(widget.game),
                  color: isOwner
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onPrimaryContainer,
                ),
              ),
        title: Text(
          isOwner ? 'Your Room' : 'Game #${widget.game.id.substring(0, 8)}',
          style: textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${gameTimingLabel(widget.game)} • ${widget.game.access.name}',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            _PlayerSlots(
              playerCount: playerCount,
              minPlayers: widget.game.minPlayers,
              maxPlayers: widget.game.maxPlayers,
              waitLabel: formatWaitDuration(widget.game.createdAt),
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
          ],
        ),
        isThreeLine: true,
        trailing: _isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : isOwner
            ? OutlinedButton(
                onPressed: _cancelGame,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  side: BorderSide(color: colorScheme.error),
                ),
                child: const Text('Cancel'),
              )
            : widget.isParticipant
            ? OutlinedButton(
                onPressed: () => context.pushNamed(
                  'game',
                  pathParameters: {'gameId': widget.game.id},
                ),
                child: const Text('View'),
              )
            : !supported
            ? const FilledButton(onPressed: null, child: Text('Update to join'))
            : ratedBlockedForGuest
            ? const FilledButton(
                onPressed: null,
                child: Text('Sign up to play rated'),
              )
            : FilledButton(onPressed: _joinGame, child: const Text('Join')),
      ),
    );
  }

  Future<void> _joinGame() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(gameRepositoryProvider)
          .joinGame(
            widget.game.id,
            clientSchemaVersion: ref
                .read(currentGameModuleProvider)
                .latestSchemaVersion,
          );
      if (!mounted) return;
      setState(() => _isLoading = false);
      await context.pushNamed(
        'game',
        pathParameters: {'gameId': widget.game.id},
      );
      if (mounted) widget.onJoined();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanize(e))));
    }
  }

  Future<void> _cancelGame() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(gameRepositoryProvider).cancelGame(widget.game.id);
      if (!mounted) return;
      setState(() => _isLoading = false);
      widget.onCancelled();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanize(e))));
    }
  }
}

/// Row of filled/empty pip dots representing player slots, plus a wait label.
class _PlayerSlots extends StatelessWidget {
  const _PlayerSlots({
    required this.playerCount,
    required this.minPlayers,
    required this.maxPlayers,
    required this.waitLabel,
    required this.colorScheme,
    required this.textTheme,
  });

  final int playerCount;
  final int minPlayers;
  final int maxPlayers;
  final String waitLabel;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    // Once playerCount >= minPlayers the game is ready: all pips are filled and
    // the fraction switches to playerCount/maxPlayers to show remaining capacity.
    // Below the threshold the fraction shows progress toward the minimum, with
    // the max appended only when the two values differ.
    final isReady = playerCount >= minPlayers;
    final fraction = isReady
        ? '$playerCount/$maxPlayers'
        : '$playerCount/$minPlayers';
    final capacitySuffix = !isReady && maxPlayers > minPlayers
        ? ' • $maxPlayers max'
        : '';
    return Row(
      children: [
        for (int i = 0; i < minPlayers; i++)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: i < playerCount
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 4),
        Text(
          '$fraction$capacitySuffix • $waitLabel',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
