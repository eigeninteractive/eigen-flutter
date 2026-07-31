// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for ProfileRepository instance.

@ProviderFor(profileRepository)
final profileRepositoryProvider = ProfileRepositoryProvider._();

/// Provider for ProfileRepository instance.

final class ProfileRepositoryProvider
    extends
        $FunctionalProvider<
          ProfileRepository,
          ProfileRepository,
          ProfileRepository
        >
    with $Provider<ProfileRepository> {
  /// Provider for ProfileRepository instance.
  ProfileRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profileRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profileRepositoryHash();

  @$internal
  @override
  $ProviderElement<ProfileRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProfileRepository create(Ref ref) {
    return profileRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProfileRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProfileRepository>(value),
    );
  }
}

String _$profileRepositoryHash() => r'78bba9b39ca9d4165245c1c76da80c1ba4596a5a';

/// Provider for AvatarStorageService instance.

@ProviderFor(avatarStorageService)
final avatarStorageServiceProvider = AvatarStorageServiceProvider._();

/// Provider for AvatarStorageService instance.

final class AvatarStorageServiceProvider
    extends
        $FunctionalProvider<
          AvatarStorageService,
          AvatarStorageService,
          AvatarStorageService
        >
    with $Provider<AvatarStorageService> {
  /// Provider for AvatarStorageService instance.
  AvatarStorageServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'avatarStorageServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$avatarStorageServiceHash();

  @$internal
  @override
  $ProviderElement<AvatarStorageService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AvatarStorageService create(Ref ref) {
    return avatarStorageService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AvatarStorageService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AvatarStorageService>(value),
    );
  }
}

String _$avatarStorageServiceHash() =>
    r'fdef1b84f1a570dbb2637b020dba3183ffad6129';

/// The signed-in user's own profile.
///
/// Kept alive for the session and persisted on native so the profile can load
/// from cache on cold start. Web fetches it again after a browser reload. The
/// network result remains authoritative on every platform.
///
/// Every mutation below re-reads the profile from the server rather than
/// patching state locally. That is not caution for its own sake: the server
/// derives fields the client does not send - it stamps `avatarUrl` itself on
/// upload, complete with the cache-buster - so a locally patched copy would
/// diverge from what every other client sees.

@ProviderFor(CurrentUserProfile)
@JsonPersist()
final currentUserProfileProvider = CurrentUserProfileProvider._();

/// The signed-in user's own profile.
///
/// Kept alive for the session and persisted on native so the profile can load
/// from cache on cold start. Web fetches it again after a browser reload. The
/// network result remains authoritative on every platform.
///
/// Every mutation below re-reads the profile from the server rather than
/// patching state locally. That is not caution for its own sake: the server
/// derives fields the client does not send - it stamps `avatarUrl` itself on
/// upload, complete with the cache-buster - so a locally patched copy would
/// diverge from what every other client sees.
@JsonPersist()
final class CurrentUserProfileProvider
    extends $AsyncNotifierProvider<CurrentUserProfile, Profile> {
  /// The signed-in user's own profile.
  ///
  /// Kept alive for the session and persisted on native so the profile can load
  /// from cache on cold start. Web fetches it again after a browser reload. The
  /// network result remains authoritative on every platform.
  ///
  /// Every mutation below re-reads the profile from the server rather than
  /// patching state locally. That is not caution for its own sake: the server
  /// derives fields the client does not send - it stamps `avatarUrl` itself on
  /// upload, complete with the cache-buster - so a locally patched copy would
  /// diverge from what every other client sees.
  CurrentUserProfileProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentUserProfileProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentUserProfileHash();

  @$internal
  @override
  CurrentUserProfile create() => CurrentUserProfile();
}

String _$currentUserProfileHash() =>
    r'3264845c76f771032e4febe7c7000377a648c36f';

/// The signed-in user's own profile.
///
/// Kept alive for the session and persisted on native so the profile can load
/// from cache on cold start. Web fetches it again after a browser reload. The
/// network result remains authoritative on every platform.
///
/// Every mutation below re-reads the profile from the server rather than
/// patching state locally. That is not caution for its own sake: the server
/// derives fields the client does not send - it stamps `avatarUrl` itself on
/// upload, complete with the cache-buster - so a locally patched copy would
/// diverge from what every other client sees.

@JsonPersist()
abstract class _$CurrentUserProfileBase extends $AsyncNotifier<Profile> {
  FutureOr<Profile> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Profile>, Profile>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Profile>, Profile>,
              AsyncValue<Profile>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

// **************************************************************************
// JsonGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
abstract class _$CurrentUserProfile extends _$CurrentUserProfileBase {
  /// The default key used by [persist].
  String get key {
    const resolvedKey = "CurrentUserProfile";
    return resolvedKey;
  }

  /// A variant of [persist], for JSON-specific encoding.
  ///
  /// You can override [key] to customize the key used for storage.
  PersistResult persist(
    FutureOr<Storage<String, String>> storage, {
    String? key,
    String Function(Profile state)? encode,
    Profile Function(String encoded)? decode,
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
            return Profile.fromJson(e as Map<String, Object?>);
          },
      options: options,
    );
  }
}
