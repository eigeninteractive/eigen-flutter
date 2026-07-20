import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_flutter/core/storage/shared_preferences_provider.dart';

part 'theme_provider.g.dart';

const _themeKey = 'theme_mode';

/// Manages the app's [ThemeMode] with persistence across sessions.
@Riverpod(keepAlive: true)
class ThemeController extends _$ThemeController {
  @override
  Future<ThemeMode> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    return _fromString(prefs.getString(_themeKey));
  }

  /// Persists [mode] and immediately updates the UI.
  Future<void> setTheme(ThemeMode mode) async {
    state = AsyncData(mode);
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setString(_themeKey, _toString(mode));
  }

  ThemeMode _fromString(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  String _toString(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}
