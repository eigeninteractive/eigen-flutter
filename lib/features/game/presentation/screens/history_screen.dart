import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:intl/intl.dart';
import 'package:eigen_flutter/core/errors/error_messages.dart';
import 'package:eigen_flutter/core/game/game_outcome.dart';
import 'package:eigen_flutter/features/game/data/game_repository.dart';
import 'package:eigen_flutter/features/game/data/models/game.dart';
import 'package:eigen_flutter/features/game/presentation/extensions/game_ui.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';
import 'package:eigen_flutter/features/rating/data/models/rating_change.dart';
import 'package:eigen_flutter/shared/widgets/empty_state_view.dart';

typedef _HistoryEntry = ({
  Game game,
  OutcomeResult? myResult,
  RatingChange? ratingChange,
});

/// Screen showing the current user's completed game history.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final PagingController<String, _HistoryEntry> _pagingController;

  @override
  void initState() {
    super.initState();
    _pagingController = PagingController<String, _HistoryEntry>(
      getNextPageKey: (state) {
        final pages = state.pages;
        if (pages == null || pages.isEmpty) return '';
        final lastPage = pages.last;
        if (lastPage.length < historyPageSize) return null;
        final last = lastPage.last.game;
        return (last.finishedAt ?? last.createdAt).toIso8601String();
      },
      fetchPage: (key) {
        final cursor = key.isEmpty ? null : DateTime.parse(key);
        return ref
            .read(gameRepositoryProvider)
            .getHistoryGameEntries(cursor: cursor);
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
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async => _pagingController.refresh(),
      child: PagingListener(
        controller: _pagingController,
        builder: (context, state, fetchNextPage) =>
            PagedListView<String, _HistoryEntry>(
              state: state,
              fetchNextPage: fetchNextPage,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              builderDelegate: PagedChildBuilderDelegate<_HistoryEntry>(
                animateTransitions: true,
                itemBuilder: (context, entry, _) =>
                    _HistoryCard(key: ValueKey(entry.game.id), entry: entry),
                noItemsFoundIndicatorBuilder: (_) => EmptyStateView(
                  icon: Icons.history,
                  title: 'No finished games yet',
                  message: 'Completed games will appear here.',
                  cta: 'Play your first game',
                  onCta: () => context.go('/lobby'),
                  tonalCta: true,
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

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({super.key, required this.entry});

  final _HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final game = entry.game;
    final result = entry.myResult;
    final ratingChange = entry.ratingChange;

    final locale = Localizations.localeOf(context).toString();
    final date = game.finishedAt ?? game.updatedAt;
    final dateLabel = DateFormat.yMMMd(locale).format(date.toLocal());

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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: result.color(colorScheme).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(result.icon, color: result.color(colorScheme)),
              ),
              const SizedBox(width: 16),
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
                      '${result.label} • $dateLabel',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (ratingChange != null) ...[
                      const SizedBox(height: 6),
                      _RatingDelta(change: ratingChange),
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

class _RatingDelta extends StatelessWidget {
  const _RatingDelta({required this.change});

  final RatingChange change;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final poolName = change.pool[0].toUpperCase() + change.pool.substring(1);

    final Color color;
    final String triangle;
    final String amount;
    if (change.displayChange > 0) {
      color = colorScheme.tertiary;
      triangle = '▲';
      amount = '+${change.displayChange}';
    } else if (change.displayChange < 0) {
      color = colorScheme.error;
      triangle = '▼';
      amount = '${change.displayChange}';
    } else {
      color = colorScheme.onSurfaceVariant;
      triangle = '–';
      amount = '0';
    }

    return Text(
      '$triangle $amount $poolName',
      style: textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
