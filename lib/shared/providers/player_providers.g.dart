// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Singleton [PlayerRepository] instance.

@ProviderFor(playerRepository)
final playerRepositoryProvider = PlayerRepositoryProvider._();

/// Singleton [PlayerRepository] instance.

final class PlayerRepositoryProvider
    extends
        $FunctionalProvider<
          PlayerRepository,
          PlayerRepository,
          PlayerRepository
        >
    with $Provider<PlayerRepository> {
  /// Singleton [PlayerRepository] instance.
  PlayerRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playerRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playerRepositoryHash();

  @$internal
  @override
  $ProviderElement<PlayerRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlayerRepository create(Ref ref) {
    return playerRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlayerRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlayerRepository>(value),
    );
  }
}

String _$playerRepositoryHash() => r'27c1100badb97e583e6cd43c48994cb7d15f859e';

/// Coalesces the per-id [PlayerInfoCache] misses into one batch request.
///
/// A session-lived singleton so its batching window spans the whole app: every
/// id watched in a single widget build funnels through one [PlayerBatchLoader]
/// and one network call. See [PlayerBatchLoader] for why a zero-delay window
/// suffices.

@ProviderFor(playerBatchLoader)
final playerBatchLoaderProvider = PlayerBatchLoaderProvider._();

/// Coalesces the per-id [PlayerInfoCache] misses into one batch request.
///
/// A session-lived singleton so its batching window spans the whole app: every
/// id watched in a single widget build funnels through one [PlayerBatchLoader]
/// and one network call. See [PlayerBatchLoader] for why a zero-delay window
/// suffices.

final class PlayerBatchLoaderProvider
    extends
        $FunctionalProvider<
          PlayerBatchLoader,
          PlayerBatchLoader,
          PlayerBatchLoader
        >
    with $Provider<PlayerBatchLoader> {
  /// Coalesces the per-id [PlayerInfoCache] misses into one batch request.
  ///
  /// A session-lived singleton so its batching window spans the whole app: every
  /// id watched in a single widget build funnels through one [PlayerBatchLoader]
  /// and one network call. See [PlayerBatchLoader] for why a zero-delay window
  /// suffices.
  PlayerBatchLoaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playerBatchLoaderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playerBatchLoaderHash();

  @$internal
  @override
  $ProviderElement<PlayerBatchLoader> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlayerBatchLoader create(Ref ref) {
    return playerBatchLoader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlayerBatchLoader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlayerBatchLoader>(value),
    );
  }
}

String _$playerBatchLoaderHash() => r'b304409a3f6b309cde08d35a10fd8138c53ce989';

/// Globally cached public player identity by ID.
///
/// Works for both human users and bots; the batch endpoint covers both.
/// `keepAlive: true` keeps the result in memory for the session lifetime.
/// Native apps also restore it from the local API cache before the network
/// response arrives. Web fetches fresh data after a browser reload.
///
/// Player identity is public data, so the cache is never cleared on sign-out.
/// Bump [StorageOptions.destroyKey] if [Player]'s JSON schema changes.

@ProviderFor(PlayerInfoCache)
@JsonPersist()
final playerInfoCacheProvider = PlayerInfoCacheFamily._();

/// Globally cached public player identity by ID.
///
/// Works for both human users and bots; the batch endpoint covers both.
/// `keepAlive: true` keeps the result in memory for the session lifetime.
/// Native apps also restore it from the local API cache before the network
/// response arrives. Web fetches fresh data after a browser reload.
///
/// Player identity is public data, so the cache is never cleared on sign-out.
/// Bump [StorageOptions.destroyKey] if [Player]'s JSON schema changes.
@JsonPersist()
final class PlayerInfoCacheProvider
    extends $AsyncNotifierProvider<PlayerInfoCache, Player> {
  /// Globally cached public player identity by ID.
  ///
  /// Works for both human users and bots; the batch endpoint covers both.
  /// `keepAlive: true` keeps the result in memory for the session lifetime.
  /// Native apps also restore it from the local API cache before the network
  /// response arrives. Web fetches fresh data after a browser reload.
  ///
  /// Player identity is public data, so the cache is never cleared on sign-out.
  /// Bump [StorageOptions.destroyKey] if [Player]'s JSON schema changes.
  PlayerInfoCacheProvider._({
    required PlayerInfoCacheFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'playerInfoCacheProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$playerInfoCacheHash();

  @override
  String toString() {
    return r'playerInfoCacheProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PlayerInfoCache create() => PlayerInfoCache();

  @override
  bool operator ==(Object other) {
    return other is PlayerInfoCacheProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$playerInfoCacheHash() => r'780b668d15edf866ab1ca930436510fe003197c8';

/// Globally cached public player identity by ID.
///
/// Works for both human users and bots; the batch endpoint covers both.
/// `keepAlive: true` keeps the result in memory for the session lifetime.
/// Native apps also restore it from the local API cache before the network
/// response arrives. Web fetches fresh data after a browser reload.
///
/// Player identity is public data, so the cache is never cleared on sign-out.
/// Bump [StorageOptions.destroyKey] if [Player]'s JSON schema changes.

@JsonPersist()
final class PlayerInfoCacheFamily extends $Family
    with
        $ClassFamilyOverride<
          PlayerInfoCache,
          AsyncValue<Player>,
          Player,
          FutureOr<Player>,
          String
        > {
  PlayerInfoCacheFamily._()
    : super(
        retry: null,
        name: r'playerInfoCacheProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Globally cached public player identity by ID.
  ///
  /// Works for both human users and bots; the batch endpoint covers both.
  /// `keepAlive: true` keeps the result in memory for the session lifetime.
  /// Native apps also restore it from the local API cache before the network
  /// response arrives. Web fetches fresh data after a browser reload.
  ///
  /// Player identity is public data, so the cache is never cleared on sign-out.
  /// Bump [StorageOptions.destroyKey] if [Player]'s JSON schema changes.

  @JsonPersist()
  PlayerInfoCacheProvider call({required String id}) =>
      PlayerInfoCacheProvider._(argument: id, from: this);

  @override
  String toString() => r'playerInfoCacheProvider';
}

/// Globally cached public player identity by ID.
///
/// Works for both human users and bots; the batch endpoint covers both.
/// `keepAlive: true` keeps the result in memory for the session lifetime.
/// Native apps also restore it from the local API cache before the network
/// response arrives. Web fetches fresh data after a browser reload.
///
/// Player identity is public data, so the cache is never cleared on sign-out.
/// Bump [StorageOptions.destroyKey] if [Player]'s JSON schema changes.

@JsonPersist()
abstract class _$PlayerInfoCacheBase extends $AsyncNotifier<Player> {
  late final _$args = ref.$arg as String;
  String get id => _$args;

  FutureOr<Player> build({required String id});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Player>, Player>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Player>, Player>,
              AsyncValue<Player>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(id: _$args));
  }
}

// **************************************************************************
// JsonGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
abstract class _$PlayerInfoCache extends _$PlayerInfoCacheBase {
  /// The default key used by [persist].
  String get key {
    late final args = id;
    late final resolvedKey = 'PlayerInfoCache($args)';

    return resolvedKey;
  }

  /// A variant of [persist], for JSON-specific encoding.
  ///
  /// You can override [key] to customize the key used for storage.
  PersistResult persist(
    FutureOr<Storage<String, String>> storage, {
    String? key,
    String Function(Player state)? encode,
    Player Function(String encoded)? decode,
    StorageOptions options = const StorageOptions(),
  }) {
    return NotifierPersistX(this).persist<String, String>(
      storage,
      key: key ?? this.key,
      encode: encode ?? $jsonCodex.encode,
      decode:
          decode ??
          (encoded) {
            final e = $jsonCodex.decode(encoded);
            return Player.fromJson(e as Map<String, Object?>);
          },
      options: options,
    );
  }
}
