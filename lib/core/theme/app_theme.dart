import 'package:flutter/material.dart';

/// Minimal app theme configuration using Material 3.
///
/// Colour is derived from a seed supplied by `Branding` (see
/// `core/config/app_config.dart`) — call [light]/[dark] with that seed.
/// Typography pairs two faces bundled by this package (see `fonts:` in the
/// engine `pubspec.yaml`), so both render offline from the first frame and
/// consuming apps need no font wiring. Built themes are cached per seed and
/// display family so rebuilds never regenerate the [ColorScheme].
abstract final class AppTheme {
  /// Package-qualified family for the engine-bundled Inter.
  ///
  /// Fonts declared in a package's `pubspec.yaml` are registered under the
  /// `packages/<package>/<family>` namespace, so this prefix is required even
  /// from within the engine itself.
  static const String inter = 'packages/eigen_flutter/Inter';

  /// Package-qualified family for the engine-bundled Space Grotesk.
  static const String spaceGrotesk = 'packages/eigen_flutter/Space Grotesk';

  static const SnackBarThemeData _snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
  );

  static final Map<(Color, String), ThemeData> _lightCache = {};
  static final Map<(Color, String), ThemeData> _darkCache = {};

  /// The Material 3 text theme with [display] on the display and headline
  /// roles and Inter everywhere else.
  ///
  /// The split is a property of the faces rather than a preference. Space
  /// Grotesk is drawn for size: tight sidebearings and a single-storey `g` read
  /// as character in a headline and as noise in a paragraph. Inter is drawn for
  /// UI at small sizes and has the taller x-height to prove it. So the roles a
  /// player *reads* — body, label, and the title role that labels list rows —
  /// stay on Inter, and only the roles they glance at take the display face.
  ///
  /// Applying the families here rather than through [ThemeData.fontFamily]
  /// keeps every other property of the Material 3 type scale — sizes, weights,
  /// tracking, line heights — exactly as the framework defines it, which is
  /// what makes this survive the move to Material Expressive.
  static TextTheme textTheme(TextTheme base, String display) => base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontFamily: display),
    displayMedium: base.displayMedium?.copyWith(fontFamily: display),
    displaySmall: base.displaySmall?.copyWith(fontFamily: display),
    headlineLarge: base.headlineLarge?.copyWith(fontFamily: display),
    headlineMedium: base.headlineMedium?.copyWith(fontFamily: display),
    headlineSmall: base.headlineSmall?.copyWith(fontFamily: display),
  );

  static ThemeData _build(
    Color seedColor,
    String display,
    Brightness brightness,
  ) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      // Inter is the default for everything, including the widgets that build
      // their own text styles rather than reading the text theme.
      fontFamily: inter,
      snackBarTheme: _snackBarTheme,
    );
    return theme.copyWith(textTheme: textTheme(theme.textTheme, display));
  }

  /// Light theme for [seedColor], with [display] on the display and headline
  /// roles. Cached per pair.
  static ThemeData light(Color seedColor, {String display = spaceGrotesk}) =>
      _lightCache.putIfAbsent((
        seedColor,
        display,
      ), () => _build(seedColor, display, Brightness.light));

  /// Dark theme for [seedColor], with [display] on the display and headline
  /// roles. Cached per pair.
  static ThemeData dark(Color seedColor, {String display = spaceGrotesk}) =>
      _darkCache.putIfAbsent((
        seedColor,
        display,
      ), () => _build(seedColor, display, Brightness.dark));
}
