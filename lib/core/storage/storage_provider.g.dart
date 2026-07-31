// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Platform storage backend for persisted Riverpod providers.
///
/// Native apps use Riverpod's SQLite adapter; web uses browser LocalStorage
/// through SharedPreferencesAsync. Both store the same JSON + expiry metadata
/// behind Riverpod's Storage contract.

@ProviderFor(storage)
final storageProvider = StorageProvider._();

/// Platform storage backend for persisted Riverpod providers.
///
/// Native apps use Riverpod's SQLite adapter; web uses browser LocalStorage
/// through SharedPreferencesAsync. Both store the same JSON + expiry metadata
/// behind Riverpod's Storage contract.

final class StorageProvider
    extends
        $FunctionalProvider<
          AsyncValue<Storage<String, String>>,
          Storage<String, String>,
          FutureOr<Storage<String, String>>
        >
    with
        $FutureModifier<Storage<String, String>>,
        $FutureProvider<Storage<String, String>> {
  /// Platform storage backend for persisted Riverpod providers.
  ///
  /// Native apps use Riverpod's SQLite adapter; web uses browser LocalStorage
  /// through SharedPreferencesAsync. Both store the same JSON + expiry metadata
  /// behind Riverpod's Storage contract.
  StorageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'storageProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storageHash();

  @$internal
  @override
  $FutureProviderElement<Storage<String, String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Storage<String, String>> create(Ref ref) {
    return storage(ref);
  }
}

String _$storageHash() => r'ddcf81be4a07ce53bf91fbb07e81b143dcea879a';
