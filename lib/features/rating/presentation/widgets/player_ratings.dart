import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_flutter/core/errors/error_messages.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/features/rating/presentation/extensions/rating_ui.dart';
import 'package:eigen_flutter/features/rating/providers/rating_providers.dart';

/// How [Ratings] renders each pool.
enum RatingsLayout {
  /// Elevated cards, two to a row — for the roomy profile screen.
  cards,

  /// Dense `pool … rating` rows — for the compact profile sheet.
  rows,
}

/// A player's ratings across every pool they have played in.
///
/// Owns the fetch and the loading, error and empty states. Callers own the
/// surrounding section chrome (heading, padding, dividers), which legitimately
/// differs between the profile screen and the profile sheet.
class PlayerRatings extends ConsumerWidget {
  /// Ratings of the signed-in user.
  const PlayerRatings.me({super.key, this.layout = RatingsLayout.cards})
    : playerId = null;

  /// Ratings of [playerId], which may be a human or a bot.
  const PlayerRatings.forPlayer(
    this.playerId, {
    super.key,
    this.layout = RatingsLayout.rows,
  });

  /// The player whose ratings to show, or null for the signed-in user.
  final String? playerId;

  /// How each pool's rating is rendered.
  final RatingsLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final id = playerId;
    final ratingsAsync = id == null
        ? ref.watch(myRatingsProvider)
        : ref.watch(playerRatingsProvider(id));

    return ratingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text(
        humanize(error),
        style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
      ),
      data: (ratings) {
        if (ratings.isEmpty) {
          return Text(
            'No rated games yet',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          );
        }
        return switch (layout) {
          RatingsLayout.cards => _RatingCards(ratings: ratings),
          RatingsLayout.rows => _RatingRows(ratings: ratings),
        };
      },
    );
  }
}

class _RatingCards extends StatelessWidget {
  const _RatingCards({required this.ratings});

  final List<Rating> ratings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = ratings.length == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final rating in ratings)
              SizedBox(
                width: cardWidth,
                child: _RatingCard(rating: rating),
              ),
          ],
        );
      },
    );
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rating.poolLabel,
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${rating.displayRating}',
              style: textTheme.headlineLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingRows extends StatelessWidget {
  const _RatingRows({required this.ratings});

  final List<Rating> ratings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [for (final rating in ratings) _RatingRow(rating: rating)],
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rating.poolLabel, style: textTheme.bodyMedium),
          Text(
            '${rating.displayRating}',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
