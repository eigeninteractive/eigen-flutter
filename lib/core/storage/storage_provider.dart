import 'package:path/path.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod_sqflite/riverpod_sqflite.dart';
import 'package:sqflite/sqflite.dart';

part 'storage_provider.g.dart';

/// SQLite storage backend for all persisted Riverpod providers.
/// Opened once and kept alive for the app lifetime.
@Riverpod(keepAlive: true)
Future<JsonSqFliteStorage> storage(Ref ref) async {
  return JsonSqFliteStorage.open(join(await getDatabasesPath(), 'riverpod.db'));
}

/// Returns the SQLite key used to persist a user's own profile.
///
/// Centralised here so [CurrentUserProfile] and [deleteUserData] stay in sync
/// without a circular import between the profile and auth feature layers.
String profileCacheKey(String userId) => 'profile_$userId';

/// Returns the SQLite key used to persist a user's friendships list.
String friendshipsCacheKey(String userId) => 'friendships_$userId';

/// Deletes all locally persisted data for [userId].
///
/// Call on sign-out and account deletion. [StorageCacheTime.unsafe_forever]
/// never expires on its own, so explicit deletion is needed when a session ends.
Future<void> deleteUserData(Ref ref, String userId) async {
  final storage = await ref.read(storageProvider.future);
  await Future.wait([
    storage.delete(profileCacheKey(userId)),
    storage.delete(friendshipsCacheKey(userId)),
  ]);
}
