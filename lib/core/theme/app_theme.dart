import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Minimal app theme configuration using Material 3.
///
/// Themes are derived from a seed color supplied by `Branding` (see
/// `core/config/app_config.dart`) — call [light]/[dark] with that seed.
/// Typography uses Google Fonts (Inter). Built themes are cached per seed so
/// rebuilds never regenerate the [ColorScheme] or the Google Fonts text theme.
abstract final class AppTheme {
  /// Cached text theme to avoid regenerating Google Fonts on every rebuild.
  static final TextTheme _textTheme = GoogleFonts.interTextTheme();
  static final TextTheme _darkTextTheme = GoogleFonts.interTextTheme(
    ThemeData.dark().textTheme,
  );

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
      textTheme: _textTheme,
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
      textTheme: _darkTextTheme,
      snackBarTheme: _snackBarTheme,
    ),
  );
}
