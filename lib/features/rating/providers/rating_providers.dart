import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/rating/data/models/player_rating.dart';
import 'package:eigen_engine/features/rating/data/rating_repository.dart';

part 'rating_providers.g.dart';

@Riverpod(keepAlive: true)
RatingRepository ratingRepository(Ref ref) =>
    RatingRepository(ref.watch(supabaseClientProvider));

/// All pool ratings for [id], ordered by highest display rating.
///
/// Works for both human user IDs and bot IDs.
@riverpod
Future<List<PlayerRating>> playerRatings(Ref ref, String id) =>
    ref.watch(ratingRepositoryProvider).getPlayerRatings(id);

/// Current user's ratings across all pools.
///
/// Auto-disposes when the profile screen is not visible, so navigation
/// to the profile page always fetches fresh data.
@riverpod
Future<List<PlayerRating>> myRatings(Ref ref) {
  // Null during the brief sign-out window before navigation completes —
  // return empty rather than crashing the disposing profile screen.
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Future.value(const []);
  return ref.watch(ratingRepositoryProvider).getPlayerRatings(userId);
}
