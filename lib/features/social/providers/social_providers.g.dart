// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'social_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(socialRepository)
final socialRepositoryProvider = SocialRepositoryProvider._();

final class SocialRepositoryProvider
    extends
        $FunctionalProvider<
          SocialRepository,
          SocialRepository,
          SocialRepository
        >
    with $Provider<SocialRepository> {
  SocialRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'socialRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$socialRepositoryHash();

  @$internal
  @override
  $ProviderElement<SocialRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SocialRepository create(Ref ref) {
    return socialRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SocialRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SocialRepository>(value),
    );
  }
}

String _$socialRepositoryHash() => r'15c29990c79f1e77bbd76c340e675898cf60936e';

/// The caller's accepted friends.
///
/// Persisted: the friend list is stable, and rendering it from cache on cold
/// start avoids a spinner on a screen that rarely changes between sessions.

@ProviderFor(Friends)
@JsonPersist()
final friendsProvider = FriendsProvider._();

/// The caller's accepted friends.
///
/// Persisted: the friend list is stable, and rendering it from cache on cold
/// start avoids a spinner on a screen that rarely changes between sessions.
@JsonPersist()
final class FriendsProvider
    extends $AsyncNotifierProvider<Friends, List<Friend>> {
  /// The caller's accepted friends.
  ///
  /// Persisted: the friend list is stable, and rendering it from cache on cold
  /// start avoids a spinner on a screen that rarely changes between sessions.
  FriendsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'friendsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$friendsHash();

  @$internal
  @override
  Friends create() => Friends();
}

String _$friendsHash() => r'e08415853469b641faabba84894df31de6943886';

/// The caller's accepted friends.
///
/// Persisted: the friend list is stable, and rendering it from cache on cold
/// start avoids a spinner on a screen that rarely changes between sessions.

@JsonPersist()
abstract class _$FriendsBase extends $AsyncNotifier<List<Friend>> {
  FutureOr<List<Friend>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Friend>>, List<Friend>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Friend>>, List<Friend>>,
              AsyncValue<List<Friend>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Pending requests in both directions.
///
/// Not persisted: unlike the friend list these are short-lived, and showing a
/// stale request that has since been accepted or withdrawn is worse than a
/// brief spinner.

@ProviderFor(friendRequests)
final friendRequestsProvider = FriendRequestsProvider._();

/// Pending requests in both directions.
///
/// Not persisted: unlike the friend list these are short-lived, and showing a
/// stale request that has since been accepted or withdrawn is worse than a
/// brief spinner.

final class FriendRequestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FriendRequest>>,
          List<FriendRequest>,
          FutureOr<List<FriendRequest>>
        >
    with
        $FutureModifier<List<FriendRequest>>,
        $FutureProvider<List<FriendRequest>> {
  /// Pending requests in both directions.
  ///
  /// Not persisted: unlike the friend list these are short-lived, and showing a
  /// stale request that has since been accepted or withdrawn is worse than a
  /// brief spinner.
  FriendRequestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'friendRequestsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$friendRequestsHash();

  @$internal
  @override
  $FutureProviderElement<List<FriendRequest>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<FriendRequest>> create(Ref ref) {
    return friendRequests(ref);
  }
}

String _$friendRequestsHash() => r'0d6b0d52d5cf1ff2b6a39391bebfdcfb6c6786de';

/// Requests the caller received and can act on.

@ProviderFor(incomingRequests)
final incomingRequestsProvider = IncomingRequestsProvider._();

/// Requests the caller received and can act on.

final class IncomingRequestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FriendRequest>>,
          List<FriendRequest>,
          FutureOr<List<FriendRequest>>
        >
    with
        $FutureModifier<List<FriendRequest>>,
        $FutureProvider<List<FriendRequest>> {
  /// Requests the caller received and can act on.
  IncomingRequestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'incomingRequestsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$incomingRequestsHash();

  @$internal
  @override
  $FutureProviderElement<List<FriendRequest>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<FriendRequest>> create(Ref ref) {
    return incomingRequests(ref);
  }
}

String _$incomingRequestsHash() => r'936cc7ee2caae1583641e9c61a00f4975194548f';

/// Requests the caller sent and can withdraw.

@ProviderFor(outgoingRequests)
final outgoingRequestsProvider = OutgoingRequestsProvider._();

/// Requests the caller sent and can withdraw.

final class OutgoingRequestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FriendRequest>>,
          List<FriendRequest>,
          FutureOr<List<FriendRequest>>
        >
    with
        $FutureModifier<List<FriendRequest>>,
        $FutureProvider<List<FriendRequest>> {
  /// Requests the caller sent and can withdraw.
  OutgoingRequestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outgoingRequestsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outgoingRequestsHash();

  @$internal
  @override
  $FutureProviderElement<List<FriendRequest>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<FriendRequest>> create(Ref ref) {
    return outgoingRequests(ref);
  }
}

String _$outgoingRequestsHash() => r'2db8f6db28e606e188320c4ddc46661280867f2a';

/// Joinable games created by the caller's friends.

@ProviderFor(friendsGames)
final friendsGamesProvider = FriendsGamesProvider._();

/// Joinable games created by the caller's friends.

final class FriendsGamesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<GameSummary>>,
          List<GameSummary>,
          FutureOr<List<GameSummary>>
        >
    with
        $FutureModifier<List<GameSummary>>,
        $FutureProvider<List<GameSummary>> {
  /// Joinable games created by the caller's friends.
  FriendsGamesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'friendsGamesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$friendsGamesHash();

  @$internal
  @override
  $FutureProviderElement<List<GameSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<GameSummary>> create(Ref ref) {
    return friendsGames(ref);
  }
}

String _$friendsGamesHash() => r'd2418a76d6c91fefa247c31f379503f3edb0fd38';

@ProviderFor(friendStatus)
final friendStatusProvider = FriendStatusFamily._();

final class FriendStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<FriendStatus>,
          FriendStatus,
          FutureOr<FriendStatus>
        >
    with $FutureModifier<FriendStatus>, $FutureProvider<FriendStatus> {
  FriendStatusProvider._({
    required FriendStatusFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'friendStatusProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$friendStatusHash();

  @override
  String toString() {
    return r'friendStatusProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<FriendStatus> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<FriendStatus> create(Ref ref) {
    final argument = this.argument as String;
    return friendStatus(ref, targetId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FriendStatusProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$friendStatusHash() => r'5b2fb974366aaece34a0cb0bab2ee27f2724f444';

final class FriendStatusFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<FriendStatus>, String> {
  FriendStatusFamily._()
    : super(
        retry: null,
        name: r'friendStatusProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FriendStatusProvider call({required String targetId}) =>
      FriendStatusProvider._(argument: targetId, from: this);

  @override
  String toString() => r'friendStatusProvider';
}

// **************************************************************************
// JsonGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
abstract class _$Friends extends _$FriendsBase {
  /// The default key used by [persist].
  String get key {
    const resolvedKey = "Friends";
    return resolvedKey;
  }

  /// A variant of [persist], for JSON-specific encoding.
  ///
  /// You can override [key] to customize the key used for storage.
  PersistResult persist(
    FutureOr<Storage<String, String>> storage, {
    String? key,
    String Function(List<Friend> state)? encode,
    List<Friend> Function(String encoded)? decode,
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
            return (e as List)
                .map((e) => Friend.fromJson(e as Map<String, Object?>))
                .toList();
          },
      options: options,
    );
  }
}
