import 'package:checks/checks.dart';
import 'package:eigen_flutter/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('puts the display face on the roles that are glanced at, not read', () {
    final theme = AppTheme.light(Colors.teal);
    final text = theme.textTheme;

    // Space Grotesk is drawn for size. These are the roles a player glances at.
    check(text.displayLarge!.fontFamily).equals(AppTheme.spaceGrotesk);
    check(text.headlineMedium!.fontFamily).equals(AppTheme.spaceGrotesk);

    // Everything read at length stays on Inter, including the title role, which
    // labels list rows rather than heading a screen.
    check(text.titleMedium!.fontFamily).equals(AppTheme.inter);
    check(text.bodyLarge!.fontFamily).equals(AppTheme.inter);
    check(text.labelSmall!.fontFamily).equals(AppTheme.inter);

    // Widgets that build their own styles rather than reading the text theme
    // fall back to this, so it has to be the body face.
    check(theme.textTheme.bodyMedium!.fontFamily).equals(AppTheme.inter);
  });

  test('keeps the Material 3 type scale apart from the family', () {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    ).textTheme;
    final themed = AppTheme.light(Colors.teal).textTheme;

    // Only the family changes. Sizes, weights, tracking and line heights stay
    // as the framework defines them, which is what carries this through to
    // Material Expressive.
    check(themed.displayLarge!.fontSize).equals(base.displayLarge!.fontSize);
    check(
      themed.displayLarge!.fontWeight,
    ).equals(base.displayLarge!.fontWeight);
    check(
      themed.displayLarge!.letterSpacing,
    ).equals(base.displayLarge!.letterSpacing);
    check(themed.headlineSmall!.height).equals(base.headlineSmall!.height);
  });

  test('an app can opt out of the display face without losing the theme', () {
    final single = AppTheme.light(Colors.teal, display: AppTheme.inter);

    check(single.textTheme.displayLarge!.fontFamily).equals(AppTheme.inter);
    check(single.textTheme.bodyLarge!.fontFamily).equals(AppTheme.inter);
  });

  test('caches per seed and display family rather than per seed alone', () {
    final a = AppTheme.light(Colors.teal);
    final b = AppTheme.light(Colors.teal);
    final c = AppTheme.light(Colors.teal, display: AppTheme.inter);

    check(identical(a, b)).isTrue();
    // The cache key has to carry the family too, or the first caller's choice
    // would be handed to everyone after them.
    check(identical(a, c)).isFalse();
  });

  test('derives both brightnesses from the seed', () {
    check(
      AppTheme.light(Colors.teal).colorScheme.brightness,
    ).equals(Brightness.light);
    check(
      AppTheme.dark(Colors.teal).colorScheme.brightness,
    ).equals(Brightness.dark);
  });
}
