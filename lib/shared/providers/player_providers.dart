import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:riverpod_annotation/experimental/json_persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_engine/core/storage/storage_provider.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/shared/data/models/player_info.dart';
import 'package:eigen_engine/shared/data/player_repository.dart';

part 'player_providers.g.dart';

/// Singleton [PlayerRepository] instance.
@Riverpod(keepAlive: true)
PlayerRepository playerRepository(Ref ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return PlayerRepository(supabase);
}

/// Globally cached public player identity by ID, persisted to SQLite.
///
/// Works for both human users and bots — `get_players` covers both via a UNION.
/// `keepAlive: true` keeps the result in memory for the session lifetime.
/// `@JsonPersist()` adds SQLite persistence so cold-start lookups resolve
/// from cache (~5 ms) before the network response arrives, eliminating
/// per-player spinners when re-entering the app.
///
/// Player identity is public data — the cache is never cleared on sign-out.
/// Bump [StorageOptions.destroyKey] if [PlayerInfo]'s JSON schema changes.
@Riverpod(keepAlive: true)
@JsonPersist()
class PlayerInfoCache extends _$PlayerInfoCache {
  @override
  Future<PlayerInfo> build({required String id}) async {
    persist(
      ref.watch(storageProvider.future),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        destroyKey: '1',
      ),
    );

    final repository = ref.watch(playerRepositoryProvider);
    return repository.getPlayer(id);
  }
}
