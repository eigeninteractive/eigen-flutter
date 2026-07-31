// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Native storage backend for persisted Riverpod API snapshots.
///
/// Do not read this provider unless [persistentApiCacheEnabled] is true.

@ProviderFor(storage)
final storageProvider = StorageProvider._();

/// Native storage backend for persisted Riverpod API snapshots.
///
/// Do not read this provider unless [persistentApiCacheEnabled] is true.

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
  /// Native storage backend for persisted Riverpod API snapshots.
  ///
  /// Do not read this provider unless [persistentApiCacheEnabled] is true.
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
