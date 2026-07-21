import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:eigen_flutter/features/game/presentation/extensions/game_ui.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';
import 'package:eigen_flutter/features/rating/presentation/widgets/player_ratings.dart';
import 'package:eigen_flutter/features/social/presentation/widgets/friend_actions.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/shared/providers/player_providers.dart';
import 'package:eigen_flutter/shared/widgets/player_avatar.dart';
import 'package:eigen_flutter/shared/widgets/player_tags.dart';

/// Modal bottom sheet showing a player's public profile.
///
/// Displays identity, ratings across all pools, and — for registered human
/// players — friendship status with actions to add, accept, decline, or
/// remove. Bots and anonymous guests show identity and ratings only: bots
/// have no social features, and guests cannot be friended (server-enforced),
/// so the sheet tags them and omits the section.
///
/// Use [PlayerProfileSheet.show] to present the sheet.
class PlayerProfileSheet extends ConsumerWidget {
  const PlayerProfileSheet({
    super.key,
    required this.playerId,
    required this.type,
    required this.scrollController,
  });

  /// The player's UUID (human or bot).
  final String playerId;

  /// Whether this player is a human or bot.
  final SeatTypeEnum type;

  /// Scroll controller from the enclosing [DraggableScrollableSheet].
  final ScrollController scrollController;

  /// Shows the profile sheet for [playerId] as a modal bottom sheet.
  static void show(
    BuildContext context, {
    required String playerId,
    required SeatTypeEnum type,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => PlayerProfileSheet(
          playerId: playerId,
          type: type,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final AsyncValue<Player> playerAsync = ref.watch(
      playerInfoCacheProvider(id: playerId),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: ColoredBox(
        color: colorScheme.surface,
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            const SliverToBoxAdapter(child: _DragHandle()),
            SliverToBoxAdapter(
              child: playerAsync.when(
                data: (player) => _Header(player: player, type: type),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => const _DeletedPlayerHeader(),
              ),
            ),
            SliverToBoxAdapter(
              child: _SheetSection(
                title: 'Ratings',
                child: PlayerRatings.forPlayer(playerId),
              ),
            ),
            SliverToBoxAdapter(
              child: _RecentGamesSection(playerId: playerId, type: type),
            ),
            // Social section only for resolved, registered humans. While
            // identity is still loading (or failed: deleted account) the
            // section stays hidden rather than flashing an Add Friend button
            // at a player who may turn out to be a guest.
            if (type == SeatTypeEnum.human &&
                playerAsync.value?.isAnonymous == false)
              SliverToBoxAdapter(child: _SocialSection(playerId: playerId)),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.player, required this.type});

  final Player player;
  final SeatTypeEnum type;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          PlayerAvatar(
            avatarUrl: player.avatarUrl,
            radius: 40,
            isBot: type == SeatTypeEnum.bot,
          ),
          const SizedBox(height: 16),
          Text(
            player.displayName,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '@${player.username}',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (type == SeatTypeEnum.bot) ...[
            const SizedBox(height: 12),
            const BotTag(),
          ] else if (player.isAnonymous) ...[
            const SizedBox(height: 12),
            const GuestTag(),
          ],
        ],
      ),
    );
  }
}

class _DeletedPlayerHeader extends StatelessWidget {
  const _DeletedPlayerHeader();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.person_off_outlined,
              size: 36,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Player not found',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'This account no longer exists.',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled section of the sheet, separated from the one above by a divider.
class _SheetSection extends StatelessWidget {
  const _SheetSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Recent games section ──────────────────────────────────────────────────────

/// A player's recent public finished games, each opening its replay.
///
/// Hidden entirely when the player has no public finished games (or the fetch
/// fails), so a player with nothing to show adds no empty chrome to the sheet.
class _RecentGamesSection extends ConsumerWidget {
  const _RecentGamesSection({required this.playerId, required this.type});

  final String playerId;
  final SeatTypeEnum type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No `type` needed: the endpoint matches either identity column, so a bot's
    // history resolves from its id exactly as a human's does.
    final gamesAsync = ref.watch(
      playerPublicFinishedGamesProvider(playerId: playerId),
    );

    final games = gamesAsync.whenOrNull(data: (g) => g) ?? const [];
    if (games.isEmpty) return const SizedBox.shrink();

    return _SheetSection(
      title: 'Recent games',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final game in games)
            _RecentGameRow(game: game, result: _resultFor(game, playerId)),
        ],
      ),
    );
  }
}

/// The viewed player's own result in a finished game.
///
/// Read off the summary's outcomes rather than fetched: the list response
/// already carries every seat's result, so a row needs nothing more.
OutcomeResultEnum? _resultFor(GameSummary game, String playerId) {
  final seat = game.participants
      .where((p) => p.userId == playerId || p.botId == playerId)
      .map((p) => p.playerIndex)
      .firstOrNull;
  if (seat == null) return null;
  return game.outcomes
      ?.where((o) => o.playerIndex == seat)
      .map((o) => o.result)
      .firstOrNull;
}

class _RecentGameRow extends StatelessWidget {
  const _RecentGameRow({required this.game, required this.result});

  final GameSummary game;
  final OutcomeResultEnum? result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final date = DateTime.fromMillisecondsSinceEpoch(
      game.finishedAt ?? game.updatedAt,
    );
    final dateLabel = DateFormat.yMMMd(locale).format(date.toLocal());

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(result.icon, color: result.color(colorScheme)),
      title: Text(
        'Game #${game.id.substring(0, 8)}',
        style: textTheme.bodyLarge,
      ),
      subtitle: Text(
        '${result.label} • $dateLabel',
        style: textTheme.bodySmall,
      ),
      trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
      onTap: () {
        // Capture the router before closing the sheet — the row's context is
        // torn down by the pop.
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.pushNamed('replay', pathParameters: {'gameId': game.id});
      },
    );
  }
}

// ── Social section ────────────────────────────────────────────────────────────

class _SocialSection extends StatelessWidget {
  const _SocialSection({required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        children: [
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          FriendActions(playerId: playerId),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
