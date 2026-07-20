import 'package:flutter/material.dart';

/// Minimal app theme configuration using Material 3.
///
/// Themes are derived from a seed color supplied by `Branding` (see
/// `core/config/app_config.dart`) — call [light]/[dark] with that seed.
/// Typography uses **Inter**, bundled by this package (see `fonts:` in the
/// engine `pubspec.yaml`), so it renders offline from the first frame and
/// consuming apps need no font wiring. Setting [ThemeData.fontFamily]
/// propagates Inter across the whole default text theme at every weight. Built
/// themes are cached per seed so rebuilds never regenerate the [ColorScheme].
abstract final class AppTheme {
  /// Package-qualified family for the engine-bundled Inter font.
  ///
  /// Fonts declared in a package's `pubspec.yaml` are registered under the
  /// `packages/<package>/<family>` namespace, so this prefix is required even
  /// from within the engine itself.
  static const String _fontFamily = 'packages/eigen_flutter/Inter';

  static const SnackBarThemeData _snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
  );

  static final Map<Color, ThemeData> _lightCache = {};
  static final Map<Color, ThemeData> _darkCache = {};

  /// Light theme for [seedColor]. Cached per seed.
  static ThemeData light(Color seedColor) => _lightCache.putIfAbsent(
    seedColor,
    () => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
      fontFamily: _fontFamily,
      snackBarTheme: _snackBarTheme,
    ),
  );

  /// Dark theme for [seedColor]. Cached per seed.
  static ThemeData dark(Color seedColor) => _darkCache.putIfAbsent(
    seedColor,
    () => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      ),
      fontFamily: _fontFamily,
      snackBarTheme: _snackBarTheme,
    ),
  );
}
