// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The active [AppConfig].
///
/// [runEngineApp] registers the config for normal apps. Widget tests that
/// construct their own `ProviderScope` can override it directly:
/// ```dart
/// const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
/// const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
/// const firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
///
/// appConfigProvider.overrideWithValue(
///   AppConfig(
///     branding: const Branding(
///       appName: 'Tic Tac Toe',
///       seedColor: Colors.deepPurple,
///     ),
///     engine: EngineConfig(
///       apiBaseUrl: apiBaseUrl,
///       googleWebClientId: googleWebClientId,
///       firebaseVapidKey: firebaseVapidKey,
///     ),
///   ),
/// )
/// ```
/// Throws [UnimplementedError] at startup if no override is provided.

@ProviderFor(appConfig)
final appConfigProvider = AppConfigProvider._();

/// The active [AppConfig].
///
/// [runEngineApp] registers the config for normal apps. Widget tests that
/// construct their own `ProviderScope` can override it directly:
/// ```dart
/// const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
/// const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
/// const firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
///
/// appConfigProvider.overrideWithValue(
///   AppConfig(
///     branding: const Branding(
///       appName: 'Tic Tac Toe',
///       seedColor: Colors.deepPurple,
///     ),
///     engine: EngineConfig(
///       apiBaseUrl: apiBaseUrl,
///       googleWebClientId: googleWebClientId,
///       firebaseVapidKey: firebaseVapidKey,
///     ),
///   ),
/// )
/// ```
/// Throws [UnimplementedError] at startup if no override is provided.

final class AppConfigProvider
    extends $FunctionalProvider<AppConfig, AppConfig, AppConfig>
    with $Provider<AppConfig> {
  /// The active [AppConfig].
  ///
  /// [runEngineApp] registers the config for normal apps. Widget tests that
  /// construct their own `ProviderScope` can override it directly:
  /// ```dart
  /// const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  /// const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  /// const firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
  ///
  /// appConfigProvider.overrideWithValue(
  ///   AppConfig(
  ///     branding: const Branding(
  ///       appName: 'Tic Tac Toe',
  ///       seedColor: Colors.deepPurple,
  ///     ),
  ///     engine: EngineConfig(
  ///       apiBaseUrl: apiBaseUrl,
  ///       googleWebClientId: googleWebClientId,
  ///       firebaseVapidKey: firebaseVapidKey,
  ///     ),
  ///   ),
  /// )
  /// ```
  /// Throws [UnimplementedError] at startup if no override is provided.
  AppConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appConfigHash();

  @$internal
  @override
  $ProviderElement<AppConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppConfig create(Ref ref) {
    return appConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppConfig>(value),
    );
  }
}

String _$appConfigHash() => r'326f1a137d46d6d48060c82e4dab6068d2d20a0c';
