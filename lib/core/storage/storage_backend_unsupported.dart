import 'package:flutter_riverpod/experimental/persist.dart';

/// Reports that persisted API caching is unavailable on this platform.
Future<Storage<String, String>> openJsonStorage() async {
  throw UnsupportedError(
    'Persisted API caching is available only on native platforms.',
  );
}
