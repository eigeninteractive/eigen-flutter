import 'dart:convert';

import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens a small JSON cache backed by browser LocalStorage.
///
/// `riverpod_sqflite` is the official native adapter but has no web platform.
/// The persisted values here are small, non-critical API snapshots, which is
/// exactly the supported use-case for SharedPreferencesAsync on web.
Future<Storage<String, String>> openJsonStorage() async {
  final storage = WebJsonStorage(
    SharedPreferencesStringStore(SharedPreferencesAsync()),
  );
  await storage.deleteOutOfDate();
  return storage;
}

/// Minimal asynchronous string store used by [WebJsonStorage].
///
/// Keeping the Riverpod adapter independent of plugin registration makes its
/// expiry and eviction policy testable in a browser runner. Production still
/// delegates to the endorsed `shared_preferences` web implementation below.
abstract interface class AsyncStringStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
  Future<Map<String, Object?>> getAll();
}

/// [AsyncStringStore] backed by `shared_preferences`.
final class SharedPreferencesStringStore implements AsyncStringStore {
  SharedPreferencesStringStore(this._preferences);

  final SharedPreferencesAsync _preferences;

  @override
  Future<Map<String, Object?>> getAll() => _preferences.getAll();

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> remove(String key) => _preferences.remove(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
}

/// Riverpod JSON storage backed by browser LocalStorage.
///
/// The entry cap is a final safety net in addition to provider expiry. Public
/// player identities are keyed individually and could otherwise accumulate
/// forever as someone encounters more opponents. Oldest writes are evicted
/// first; every value remains a disposable cache miss when absent.
final class WebJsonStorage extends Storage<String, String> {
  WebJsonStorage(
    this._preferences, {
    this.maxEntries = 512,
    this.keyPrefix = 'eigen.riverpod.',
  }) : assert(maxEntries > 0);

  final int maxEntries;
  final String keyPrefix;

  final AsyncStringStore _preferences;

  String _key(String key) => '$keyPrefix$key';

  @override
  Future<PersistedData<String>?> read(String key) async {
    final encoded = await _preferences.getString(_key(key));
    if (encoded == null) return null;
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      final expireAt = value['expireAt'] as int?;
      if (expireAt != null &&
          expireAt <= DateTime.now().toUtc().millisecondsSinceEpoch) {
        await delete(key);
        return null;
      }
      return PersistedData(
        value['data'] as String,
        destroyKey: value['destroyKey'] as String?,
        expireAt: expireAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expireAt, isUtc: true),
      );
    } on Object {
      await delete(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, String value, StorageOptions options) async {
    final expireAt = switch (options.cacheTime.duration) {
      null => null,
      final duration =>
        DateTime.now().toUtc().add(duration).millisecondsSinceEpoch,
    };
    await _preferences.setString(
      _key(key),
      jsonEncode({
        'data': value,
        'expireAt': ?expireAt,
        'destroyKey': ?options.destroyKey,
        'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      }),
    );
    await _evictOverflow();
  }

  @override
  Future<void> delete(String key) => _preferences.remove(_key(key));

  @override
  Future<void> deleteOutOfDate() async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final values = await _preferences.getAll();
    await Future.wait([
      for (final entry in values.entries)
        if (entry.key.startsWith(keyPrefix) && _isExpired(entry.value, now))
          _preferences.remove(entry.key),
    ]);
  }

  Future<void> _evictOverflow() async {
    final values = await _preferences.getAll();
    final entries =
        values.entries
            .where((entry) => entry.key.startsWith(keyPrefix))
            .map(
              (entry) => (key: entry.key, updatedAt: _updatedAt(entry.value)),
            )
            .toList()
          ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final overflow = entries.length - maxEntries;
    if (overflow <= 0) return;
    await Future.wait([
      for (final entry in entries.take(overflow))
        _preferences.remove(entry.key),
    ]);
  }

  bool _isExpired(Object? encoded, int now) {
    if (encoded is! String) return true;
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      final expireAt = value['expireAt'] as int?;
      return expireAt != null && expireAt <= now;
    } on Object {
      return true;
    }
  }

  int _updatedAt(Object? encoded) {
    if (encoded is! String) return 0;
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      return value['updatedAt'] as int? ?? 0;
    } on Object {
      return 0;
    }
  }
}
