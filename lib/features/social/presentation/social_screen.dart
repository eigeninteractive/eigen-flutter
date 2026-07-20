import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_flutter/core/errors/error_messages.dart';
import 'package:eigen_flutter/core/game/participant_type.dart';
import 'package:eigen_flutter/features/social/presentation/widgets/friend_actions.dart';
import 'package:eigen_flutter/features/social/presentation/widgets/friend_buttons.dart';
import 'package:eigen_flutter/features/social/presentation/widgets/player_profile_sheet.dart';
import 'package:eigen_flutter/features/social/providers/social_providers.dart';
import 'package:eigen_flutter/shared/data/models/player_info.dart';
import 'package:eigen_flutter/shared/providers/player_providers.dart';
import 'package:eigen_flutter/shared/widgets/empty_state_view.dart';
import 'package:eigen_flutter/shared/widgets/player_avatar.dart';

class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _goToAddFriend() => _tabController.animateTo(2);

  @override
  Widget build(BuildContext context) {
    final requestCount = switch (ref.watch(pendingRequestsProvider)) {
      AsyncData(:final value) => value.length,
      _ => 0,
    };

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Friends'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Requests'),
                  if (requestCount > 0) ...[
                    const SizedBox(width: 6),
                    Badge.count(count: requestCount, smallSize: 14),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Add Friend'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _FriendsList(onFindPlayers: _goToAddFriend),
              const _PendingRequests(),
              const _AddFriend(),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Friends list ──────────────────────────────────────────────────────────────

class _FriendsList extends ConsumerStatefulWidget {
  const _FriendsList({required this.onFindPlayers});

  final VoidCallback onFindPlayers;

  @override
  ConsumerState<_FriendsList> createState() => _FriendsListState();
}

class _FriendsListState extends ConsumerState<_FriendsList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final friendsAsync = ref.watch(acceptedFriendsProvider);

    return friendsAsync.when(
      skipLoadingOnReload: true,
      data: (friendships) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(friendshipsProvider),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (friendships.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyStateView(
                  icon: Icons.people_outline,
                  title: 'No friends yet',
                  message:
                      'Add friends to stay connected and join their games.',
                  cta: 'Find Players',
                  onCta: widget.onFindPlayers,
                  tonalCta: true,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(top: 8),
                sliver: SliverList.builder(
                  itemCount: friendships.length,
                  itemBuilder: (context, index) => _FriendListTile(
                    key: ValueKey(friendships[index].friendId),
                    friendId: friendships[index].friendId,
                    variant: _FriendListVariant.friends,
                  ),
                ),
              ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: ${humanize(e)}')),
    );
  }
}

enum _FriendListVariant { friends, requests }

class _FriendListTile extends ConsumerWidget {
  const _FriendListTile({
    super.key,
    required this.friendId,
    required this.variant,
  });

  final String friendId;
  final _FriendListVariant variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerAsync = ref.watch(playerInfoCacheProvider(id: friendId));

    return playerAsync.when(
      data: (player) => ListTile(
        onTap: () => PlayerProfileSheet.show(
          context,
          playerId: friendId,
          type: ParticipantType.human,
        ),
        leading: PlayerAvatar(playerInfo: player, radius: 20),
        title: Text(player.displayName),
        subtitle: Text(
          variant == _FriendListVariant.requests
              ? '@${player.username} wants to be friends'
              : '@${player.username}',
        ),
        trailing: switch (variant) {
          _FriendListVariant.friends => RemoveFriendButton(
            playerId: friendId,
            compact: true,
          ),
          _FriendListVariant.requests => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AcceptRequestButton(playerId: friendId, compact: true),
              DeclineRequestButton(playerId: friendId, compact: true),
            ],
          ),
        },
      ),
      loading: () => ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.surfaceContainerHighest,
        ),
        title: Container(
          height: 14,
          width: 80,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      error: (e, _) => ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.surfaceContainerHighest,
          child: Icon(Icons.error_outline, color: colorScheme.error, size: 20),
        ),
        title: Text('Error: ${humanize(e)}'),
      ),
    );
  }
}

// ── Pending requests ──────────────────────────────────────────────────────────

class _PendingRequests extends ConsumerStatefulWidget {
  const _PendingRequests();

  @override
  ConsumerState<_PendingRequests> createState() => _PendingRequestsState();
}

class _PendingRequestsState extends ConsumerState<_PendingRequests>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final requestsAsync = ref.watch(pendingRequestsProvider);

    return requestsAsync.when(
      skipLoadingOnReload: true,
      data: (requests) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(friendshipsProvider),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (requests.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyStateView(
                  icon: Icons.mail_outline,
                  title: 'No pending requests',
                  message: 'Friend requests you receive will appear here.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(top: 8),
                sliver: SliverList.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) => _FriendListTile(
                    key: ValueKey(requests[index].friendId),
                    friendId: requests[index].friendId,
                    variant: _FriendListVariant.requests,
                  ),
                ),
              ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: ${humanize(e)}')),
    );
  }
}

// ── Add friend ────────────────────────────────────────────────────────────────

class _AddFriend extends ConsumerStatefulWidget {
  const _AddFriend();

  @override
  ConsumerState<_AddFriend> createState() => _AddFriendState();
}

class _AddFriendState extends ConsumerState<_AddFriend>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  List<PlayerInfo> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.length < 2) return;
    setState(() => _isLoading = true);
    try {
      final results = await ref
          .read(socialRepositoryProvider)
          .searchUsers(query);
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length >= 2) {
      _debounce = Timer(const Duration(milliseconds: 400), _search);
    } else if (_results.isNotEmpty) {
      setState(() => _results = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SearchBar(
            controller: _searchController,
            hintText: 'Search by username or display name',
            onChanged: _onSearchChanged,
            trailing: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: _isLoading ? null : _search,
              ),
            ],
            onSubmitted: (_) => _search(),
          ),
        ),
        if (_isLoading)
          const CircularProgressIndicator()
        else
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final user = _results[index];
                return ListTile(
                  key: ValueKey(user.id),
                  onTap: () => PlayerProfileSheet.show(
                    context,
                    playerId: user.id,
                    type: ParticipantType.human,
                  ),
                  leading: PlayerAvatar(playerInfo: user, radius: 20),
                  title: Text(user.displayName),
                  subtitle: Text('@${user.username}'),
                  trailing: FriendActions(playerId: user.id, compact: true),
                );
              },
            ),
          ),
      ],
    );
  }
}
