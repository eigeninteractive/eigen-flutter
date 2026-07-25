// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connectivity_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Emits the current connectivity state whenever the network changes.
///
/// Note: reflects network interface availability, not necessarily internet
/// reachability (e.g. a connected Wi-Fi with no route to the internet will
/// not report [ConnectivityResult.none]).

@ProviderFor(connectivity)
final connectivityProvider = ConnectivityProvider._();

/// Emits the current connectivity state whenever the network changes.
///
/// Note: reflects network interface availability, not necessarily internet
/// reachability (e.g. a connected Wi-Fi with no route to the internet will
/// not report [ConnectivityResult.none]).

final class ConnectivityProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ConnectivityResult>>,
          List<ConnectivityResult>,
          Stream<List<ConnectivityResult>>
        >
    with
        $FutureModifier<List<ConnectivityResult>>,
        $StreamProvider<List<ConnectivityResult>> {
  /// Emits the current connectivity state whenever the network changes.
  ///
  /// Note: reflects network interface availability, not necessarily internet
  /// reachability (e.g. a connected Wi-Fi with no route to the internet will
  /// not report [ConnectivityResult.none]).
  ConnectivityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectivityProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectivityHash();

  @$internal
  @override
  $StreamProviderElement<List<ConnectivityResult>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ConnectivityResult>> create(Ref ref) {
    return connectivity(ref);
  }
}

String _$connectivityHash() => r'59a63c90973f1e1b35f3d22e08aa91406cbfa045';

/// True when every connectivity result is [ConnectivityResult.none].
///
/// Returns false during the brief loading window before the first event.

@ProviderFor(isOffline)
final isOfflineProvider = IsOfflineProvider._();

/// True when every connectivity result is [ConnectivityResult.none].
///
/// Returns false during the brief loading window before the first event.

final class IsOfflineProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// True when every connectivity result is [ConnectivityResult.none].
  ///
  /// Returns false during the brief loading window before the first event.
  IsOfflineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isOfflineProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isOfflineHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return isOffline(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isOfflineHash() => r'4c3d8a7c4c892893b58168033657ca11dee5428f';
