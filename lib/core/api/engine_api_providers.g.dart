// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'engine_api_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app-wide HTTP client for the engine: the data layer's single backend
/// handle.
///
/// Only repositories and data services may watch this or the API providers
/// below; everything above them consumes domain types. Enforced by
/// `test/core/architecture/api_isolation_test.dart`.
///
/// The base URL is the origin only: every generated route already carries its
/// `/api/engine` prefix.
///
/// The generated `EigenApi` facade is deliberately not used, but not because it
/// can't take this Dio. It can (`EigenApi(dio: ..., interceptors: const [])`
/// installs none of its own). The reason is the split below: each repository
/// depends on the one narrow `*Api` it needs, so a fake in a test is that one
/// resource, not the whole surface. The facade would hand every repository all
/// of them.

@ProviderFor(engineDio)
final engineDioProvider = EngineDioProvider._();

/// The app-wide HTTP client for the engine: the data layer's single backend
/// handle.
///
/// Only repositories and data services may watch this or the API providers
/// below; everything above them consumes domain types. Enforced by
/// `test/core/architecture/api_isolation_test.dart`.
///
/// The base URL is the origin only: every generated route already carries its
/// `/api/engine` prefix.
///
/// The generated `EigenApi` facade is deliberately not used, but not because it
/// can't take this Dio. It can (`EigenApi(dio: ..., interceptors: const [])`
/// installs none of its own). The reason is the split below: each repository
/// depends on the one narrow `*Api` it needs, so a fake in a test is that one
/// resource, not the whole surface. The facade would hand every repository all
/// of them.

final class EngineDioProvider extends $FunctionalProvider<Dio, Dio, Dio>
    with $Provider<Dio> {
  /// The app-wide HTTP client for the engine: the data layer's single backend
  /// handle.
  ///
  /// Only repositories and data services may watch this or the API providers
  /// below; everything above them consumes domain types. Enforced by
  /// `test/core/architecture/api_isolation_test.dart`.
  ///
  /// The base URL is the origin only: every generated route already carries its
  /// `/api/engine` prefix.
  ///
  /// The generated `EigenApi` facade is deliberately not used, but not because it
  /// can't take this Dio. It can (`EigenApi(dio: ..., interceptors: const [])`
  /// installs none of its own). The reason is the split below: each repository
  /// depends on the one narrow `*Api` it needs, so a fake in a test is that one
  /// resource, not the whole surface. The facade would hand every repository all
  /// of them.
  EngineDioProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'engineDioProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$engineDioHash();

  @$internal
  @override
  $ProviderElement<Dio> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Dio create(Ref ref) {
    return engineDio(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Dio value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Dio>(value),
    );
  }
}

String _$engineDioHash() => r'68273f6df83e12fec7bb6100012b1c5863cdfa4b';

/// Server time, tracked from the `Date` header of every engine response.
///
/// Deadlines on the wire are absolute server timestamps, so every countdown in
/// the app measures against this rather than the device clock.

@ProviderFor(serverClock)
final serverClockProvider = ServerClockProvider._();

/// Server time, tracked from the `Date` header of every engine response.
///
/// Deadlines on the wire are absolute server timestamps, so every countdown in
/// the app measures against this rather than the device clock.

final class ServerClockProvider
    extends $FunctionalProvider<ServerClock, ServerClock, ServerClock>
    with $Provider<ServerClock> {
  /// Server time, tracked from the `Date` header of every engine response.
  ///
  /// Deadlines on the wire are absolute server timestamps, so every countdown in
  /// the app measures against this rather than the device clock.
  ServerClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverClockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverClockHash();

  @$internal
  @override
  $ProviderElement<ServerClock> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ServerClock create(Ref ref) {
    return serverClock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ServerClock value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ServerClock>(value),
    );
  }
}

String _$serverClockHash() => r'3305c9476050c05d8e503d96005e86648cb7520f';

/// Games, the lobby, and the frame history: the whole play surface.

@ProviderFor(gamesApi)
final gamesApiProvider = GamesApiProvider._();

/// Games, the lobby, and the frame history: the whole play surface.

final class GamesApiProvider
    extends $FunctionalProvider<GamesApi, GamesApi, GamesApi>
    with $Provider<GamesApi> {
  /// Games, the lobby, and the frame history: the whole play surface.
  GamesApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gamesApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gamesApiHash();

  @$internal
  @override
  $ProviderElement<GamesApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GamesApi create(Ref ref) {
    return gamesApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GamesApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GamesApi>(value),
    );
  }
}

String _$gamesApiHash() => r'7bbd627104ae92dc65e2c6aa9cc058f353124f3a';

/// Friends, friend requests, user search, and friends' open games.

@ProviderFor(socialApi)
final socialApiProvider = SocialApiProvider._();

/// Friends, friend requests, user search, and friends' open games.

final class SocialApiProvider
    extends $FunctionalProvider<SocialApi, SocialApi, SocialApi>
    with $Provider<SocialApi> {
  /// Friends, friend requests, user search, and friends' open games.
  SocialApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'socialApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$socialApiHash();

  @$internal
  @override
  $ProviderElement<SocialApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SocialApi create(Ref ref) {
    return socialApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SocialApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SocialApi>(value),
    );
  }
}

String _$socialApiHash() => r'738df19b580328cfe878a9d9cde7d209d737ca8b';

/// The caller's own profile, ratings, devices, username, and account deletion.

@ProviderFor(meApi)
final meApiProvider = MeApiProvider._();

/// The caller's own profile, ratings, devices, username, and account deletion.

final class MeApiProvider extends $FunctionalProvider<MeApi, MeApi, MeApi>
    with $Provider<MeApi> {
  /// The caller's own profile, ratings, devices, username, and account deletion.
  MeApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'meApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$meApiHash();

  @$internal
  @override
  $ProviderElement<MeApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MeApi create(Ref ref) {
    return meApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MeApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MeApi>(value),
    );
  }
}

String _$meApiHash() => r'17064db78b804bf61498e8db88c855f24ec09b77';

/// Batch identity lookup for rendering other players.

@ProviderFor(playersApi)
final playersApiProvider = PlayersApiProvider._();

/// Batch identity lookup for rendering other players.

final class PlayersApiProvider
    extends $FunctionalProvider<PlayersApi, PlayersApi, PlayersApi>
    with $Provider<PlayersApi> {
  /// Batch identity lookup for rendering other players.
  PlayersApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playersApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playersApiHash();

  @$internal
  @override
  $ProviderElement<PlayersApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlayersApi create(Ref ref) {
    return playersApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlayersApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlayersApi>(value),
    );
  }
}

String _$playersApiHash() => r'434215711d3904aa6b6f3aa622563d24a1930117';

/// The bot catalog offered when creating a solo game.

@ProviderFor(botsApi)
final botsApiProvider = BotsApiProvider._();

/// The bot catalog offered when creating a solo game.

final class BotsApiProvider
    extends $FunctionalProvider<BotsApi, BotsApi, BotsApi>
    with $Provider<BotsApi> {
  /// The bot catalog offered when creating a solo game.
  BotsApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'botsApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$botsApiHash();

  @$internal
  @override
  $ProviderElement<BotsApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BotsApi create(Ref ref) {
    return botsApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BotsApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BotsApi>(value),
    );
  }
}

String _$botsApiHash() => r'1276c14ace1843bc663054a7d2fa0b3845f2b4f6';

/// Opens per-game frame sockets.
///
/// Stateless and shared: one instance dials as many games as the session needs,
/// and each `connect` owns its own connection and reconnect loop.

@ProviderFor(gameSocket)
final gameSocketProvider = GameSocketProvider._();

/// Opens per-game frame sockets.
///
/// Stateless and shared: one instance dials as many games as the session needs,
/// and each `connect` owns its own connection and reconnect loop.

final class GameSocketProvider
    extends $FunctionalProvider<GameSocket, GameSocket, GameSocket>
    with $Provider<GameSocket> {
  /// Opens per-game frame sockets.
  ///
  /// Stateless and shared: one instance dials as many games as the session needs,
  /// and each `connect` owns its own connection and reconnect loop.
  GameSocketProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gameSocketProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gameSocketHash();

  @$internal
  @override
  $ProviderElement<GameSocket> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GameSocket create(Ref ref) {
    return gameSocket(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GameSocket value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GameSocket>(value),
    );
  }
}

String _$gameSocketHash() => r'37164e6253b3bd19da4031c14bb1648fcc606ec7';
