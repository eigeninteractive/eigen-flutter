@TestOn('browser')
library;

import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/storage/storage_backend_web.dart';
import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:flutter_test/flutter_test.dart';

final class _MemoryStringStore implements AsyncStringStore {
  final Map<String, Object?> _values = {};

  @override
  Future<Map<String, Object?>> getAll() async => Map.of(_values);

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }
}

void main() {
  test('persists Riverpod metadata and removes expired values', () async {
    final prefix =
        'eigen.test.${DateTime.now().microsecondsSinceEpoch}.expiration.';
    final storage = WebJsonStorage(
      _MemoryStringStore(),
      keyPrefix: prefix,
      maxEntries: 4,
    );

    await storage.write(
      'profile',
      '{"name":"Ada"}',
      const StorageOptions(
        cacheTime: StorageCacheTime(Duration.zero),
        destroyKey: '2',
      ),
    );

    check(await storage.read('profile')).isNull();
  });

  test(
    'evicts the oldest writes when the browser cache reaches its cap',
    () async {
      final prefix =
          'eigen.test.${DateTime.now().microsecondsSinceEpoch}.capacity.';
      final storage = WebJsonStorage(
        _MemoryStringStore(),
        keyPrefix: prefix,
        maxEntries: 2,
      );
      const options = StorageOptions(
        cacheTime: StorageCacheTime(Duration(days: 1)),
      );

      await storage.write('first', '1', options);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await storage.write('second', '2', options);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await storage.write('third', '3', options);

      check(await storage.read('first')).isNull();
      check((await storage.read('second'))?.data).equals('2');
      check((await storage.read('third'))?.data).equals('3');

      await storage.delete('second');
      await storage.delete('third');
    },
  );
}
