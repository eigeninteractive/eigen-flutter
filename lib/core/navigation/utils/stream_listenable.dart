import 'dart:async';

import 'package:flutter/widgets.dart';

/// Converts a [Stream] into a [Listenable]
///
/// This utility class bridges the gap between Flutter's stream-based reactive
/// programming and the [Listenable] interface required by packages like
/// go_router's refreshListenable.
///
/// Usage:
/// ```dart
/// final listenable = StreamListenable(myStream);
/// // Pass to go_router or other Listenable consumers
/// // Don't forget to dispose when done
/// listenable.dispose();
/// ```
class StreamListenable extends ChangeNotifier {
  /// Creates a [StreamListenable] that listens to [stream]
  ///
  /// Whenever the stream emits a value, [notifyListeners] is called.
  StreamListenable(Stream<dynamic> stream) {
    _subscription = stream.listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
