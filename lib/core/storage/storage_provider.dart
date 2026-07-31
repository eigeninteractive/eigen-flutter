import 'package:eigen_flutter/core/storage/storage_backend.dart';
import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_provider.g.dart';

/// Platform storage backend for persisted Riverpod providers.
///
/// Native apps use Riverpod's SQLite adapter; web uses browser LocalStorage
/// through SharedPreferencesAsync. Both store the same JSON + expiry metadata
/// behind Riverpod's Storage contract.
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
  final storage = await ref.read(storageProvider.future);
  await storage.delete(profileCacheKey(userId));
  await storage.delete(friendshipsCacheKey(userId));
}
