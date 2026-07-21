import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/engine_api_providers.dart';
import 'package:eigen_flutter/core/storage/storage_provider.dart';
import 'package:eigen_flutter/shared/data/player_repository.dart';
import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:riverpod_annotation/experimental/json_persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'player_providers.g.dart';

/// Singleton [PlayerRepository] instance.
@Riverpod(keepAlive: true)
PlayerRepository playerRepository(Ref ref) {
  return PlayerRepository(ref.watch(playersApiProvider));
}

/// Globally cached public player identity by ID, persisted to SQLite.
///
/// Works for both human users and bots — the batch endpoint covers both.
/// `keepAlive: true` keeps the result in memory for the session lifetime.
/// `@JsonPersist()` adds SQLite persistence so cold-start lookups resolve
/// from cache (~5 ms) before the network response arrives, eliminating
/// per-player spinners when re-entering the app.
///
/// Player identity is public data — the cache is never cleared on sign-out.
/// Bump [StorageOptions.destroyKey] if [Player]'s JSON schema changes.
@Riverpod(keepAlive: true)
@JsonPersist()
class PlayerInfoCache extends _$PlayerInfoCache {
  @override
  Future<Player> build({required String id}) async {
    persist(
      ref.watch(storageProvider.future),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        // Cache-schema version for the persisted Player. Bumped to 2 when the
        // hand-written PlayerInfo was replaced by the generated Player. This
        // cache is intentionally NOT cleared on sign-out (player identity is
        // public data), so the destroyKey bump is the only invalidation lever.
        destroyKey: '2',
      ),
    );

    final repository = ref.watch(playerRepositoryProvider);
    return repository.getPlayer(id);
  }
}
