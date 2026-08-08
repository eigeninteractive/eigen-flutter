import 'dart:async';

import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/shared/data/player_repository.dart';

/// Coalesces single-id player lookups into one batch request per frame.
///
/// The batch endpoint `players?ids=` is the decided alternative to
/// denormalising identity onto game rows, but the app reads identity one id at
/// a time through a per-id cache ([PlayerInfoCache]): a lobby of N games, a
/// roster of N seats. Left alone that turns one screen into N requests to a
/// *batch* endpoint, the exact N+1 the endpoint exists to avoid.
///
/// This sits between the cache and the repository and turns that back into one
/// request. [load] records the id and returns a future; a short timer then
/// fires, fetches every id collected in that window in a single call, and
/// completes each waiter.
///
/// The window is a few milliseconds rather than zero on purpose. A zero-delay
/// timer would coalesce a build only because [PlayerInfoCache.build] happens
/// to call [load] synchronously, before its first `await`, is an invisible
/// coupling that a later refactor (an `await` slipped in ahead of the load)
/// would break silently, degrading back to one request per id with no error.
/// A small real window makes coalescing robust regardless of how the callers
/// are scheduled, and the cost is imperceptible: the persisted cache already
/// paints identity in ~5 ms, so the network refresh arriving a frame later is
/// invisible. A later frame (scrolling reveals more cards) opens a fresh
/// window: one request per burst, not one per player.
///
/// The cache above already dedupes by id and holds in-flight futures, so this
/// deliberately keeps no in-flight bookkeeping of its own.
class PlayerBatchLoader {
  PlayerBatchLoader(
    this._fetch, {
    this._window = const Duration(milliseconds: 8),
  });

  /// Fetches the given ids in one request. Ids that match nothing are simply
  /// absent from the result (a purged account is a normal outcome, not an
  /// error); the loader maps that absence to [PlayerNotFoundException] for
  /// the specific waiter, exactly as a single lookup would.
  final Future<List<Player>> Function(List<String> ids) _fetch;

  final Duration _window;

  /// Ids awaiting the next flush, each with its waiters. A list per id because
  /// a caller may request the same id twice within one window (a cache
  /// invalidation racing a fresh watch); both futures must complete.
  final Map<String, List<Completer<Player>>> _pending = {};

  Timer? _timer;

  /// Resolves one player, batched with every other [load] in the same window.
  ///
  /// Throws [PlayerNotFoundException] if the id matches no player, or the
  /// underlying transport error if the batch request fails: the same
  /// outcomes a direct single lookup produces, so the cache above is unaware
  /// it was batched.
  Future<Player> load(String id) {
    final completer = Completer<Player>();
    _pending.putIfAbsent(id, () => []).add(completer);
    _timer ??= Timer(_window, _flush);
    return completer.future;
  }

  /// Cancels a pending flush. Wire to the owning provider's `ref.onDispose` so
  /// a loader replaced mid-window (its repository rebuilt) does not fire a
  /// timer that completes futures nothing awaits. A no-op when idle.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _flush() async {
    _timer = null;
    final batch = Map.of(_pending);
    _pending.clear();
    final ids = batch.keys.toList();

    try {
      final players = await _fetch(ids);
      final byId = {for (final player in players) player.id: player};
      for (final entry in batch.entries) {
        final player = byId[entry.key];
        for (final waiter in entry.value) {
          if (player != null) {
            waiter.complete(player);
          } else {
            waiter.completeError(PlayerNotFoundException(entry.key));
          }
        }
      }
    } catch (error, stackTrace) {
      // A transport failure fails the whole batch; each waiter surfaces it
      // exactly as its own request would have, and the cache provider above
      // retries per id (re-coalescing on the retry).
      for (final waiters in batch.values) {
        for (final waiter in waiters) {
          waiter.completeError(error, stackTrace);
        }
      }
    }
  }
}
