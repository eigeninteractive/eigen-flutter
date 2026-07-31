import 'package:eigen_flutter/core/storage/storage_backend.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_provider.g.dart';

/// Whether API snapshots persist across application launches on this platform.
///
/// Browser sessions keep provider state in memory and fetch fresh data after a
/// reload. Native apps temporarily use Riverpod's SQLite adapter; repository
/// caches will move to Drift when the native read model is introduced.
const persistentApiCacheEnabled = !kIsWeb;

/// Native storage backend for persisted Riverpod API snapshots.
///
/// Do not read this provider unless [persistentApiCacheEnabled] is true.
@Riverpod(keepAlive: true)
Future<Storage<String, String>> storage(Ref ref) => openJsonStorage();

/// Returns the storage key used to persist a user's own profile.
///
/// Centralised here so [CurrentUserProfile] and [deleteUserData] stay in sync
/// without a circular import between the profile and auth feature layers.
String profileCacheKey(String userId) => 'profile_$userId';

/// Returns the storage key used to persist a user's friendships list.
String friendshipsCacheKey(String userId) => 'friendships_$userId';

/// Deletes all locally persisted data for [userId].
///
/// Call on sign-out and account deletion. [StorageCacheTime.unsafe_forever]
/// never expires on its own, so explicit deletion is needed when a session ends.
Future<void> deleteUserData(Ref ref, String userId) async {
  if (!persistentApiCacheEnabled) return;
  final storage = await ref.read(storageProvider.future);
  await storage.delete(profileCacheKey(userId));
  await storage.delete(friendshipsCacheKey(userId));
}
