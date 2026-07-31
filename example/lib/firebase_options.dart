import 'package:firebase_core/firebase_core.dart';

/// Placeholder replaced by `dart run eigen_flutter:configure_firebase`.
abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw StateError(
    'Firebase is not configured. Run '
    '`dart run eigen_flutter:configure_firebase` from example/.',
  );
}
