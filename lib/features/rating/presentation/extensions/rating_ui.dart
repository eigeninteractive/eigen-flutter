import 'package:eigen_api/eigen_api.dart';

/// Display helpers for [Rating].
extension RatingUi on Rating {
  /// The pool name capitalised for display, e.g. `rapid` becomes `Rapid`.
  String get poolLabel =>
      pool.isEmpty ? pool : pool[0].toUpperCase() + pool.substring(1);
}
