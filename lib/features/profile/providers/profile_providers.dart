import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/avatar_url.dart';
import 'package:eigen_flutter/core/api/engine_api_providers.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:eigen_flutter/core/storage/storage_provider.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:eigen_flutter/features/profile/data/avatar_storage_service.dart';
import 'package:eigen_flutter/features/profile/data/profile_repository.dart';
import 'package:eigen_flutter/shared/providers/player_providers.dart';
import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:riverpod_annotation/experimental/json_persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_providers.g.dart';

/// Provider for ProfileRepository instance.
@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) {
  return ProfileRepository(ref.watch(meApiProvider));
}

/// Provider for AvatarStorageService instance.
@Riverpod(keepAlive: true)
AvatarStorageService avatarStorageService(Ref ref) {
  return AvatarStorageService(ref.watch(engineDioProvider));
}

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
@Riverpod(keepAlive: true)
@JsonPersist()
class CurrentUserProfile extends _$CurrentUserProfile {
  @override
  Future<Profile> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      throw StateError('User not authenticated');
    }

    // Native stale-while-revalidate: the local cache races the network fetch.
    // The network result overwrites silently; if it wins first, Riverpod's
    // didChange guard discards the slower cached value.
    if (persistentApiCacheEnabled) {
      persist(
        ref.watch(storageProvider.future),
        key: profileCacheKey(user.id),
        options: const StorageOptions(
          cacheTime: StorageCacheTime.unsafe_forever,
          // Cache-schema version for the persisted profile. Bumped to 2 when
          // the hand-written UserProfile was replaced by generated Profile.
          destroyKey: '2',
        ),
      );
    }

    return ref.watch(profileRepositoryProvider).getProfile();
  }

  /// Refreshes the profile from the server.
  void refresh() {
    ref.invalidateSelf();
    future.ignore();
  }

  /// Uploads [bytes] as the user's new avatar.
  ///
  /// The server stores the image and stamps the new `avatarUrl` on the profile
  /// itself, so this re-reads rather than constructing a URL locally.
  Future<void> uploadAvatar(Uint8List bytes) async {
    final current = state.value;
    if (current == null) return;

    // Evict the old image before uploading. The new URL carries a fresh
    // cache-buster so the old entry would never be requested again anyway;
    // evicting reclaims disk and memory now instead of at LRU expiry.
    final oldUrl = resolveAvatarUrl(
      current.avatarUrl,
      ref.read(appConfigProvider).engine.apiBaseUrl,
    );
    if (oldUrl != null) await CachedNetworkImageProvider(oldUrl).evict();

    state = const AsyncLoading<Profile>();
    try {
      await ref.read(avatarStorageServiceProvider).uploadAvatar(bytes);
      await _reload(current);
    } catch (_) {
      await _restore(current);
      rethrow;
    }
  }

  /// Applies whichever of [username] and [displayName] actually changed.
  ///
  /// The two are separate endpoints because they are different things: the
  /// username is unique and charset-constrained (and so can fail with
  /// [ErrorCode.usernameTaken] or [ErrorCode.usernameInvalid]), while the
  /// display name is free-form and cannot collide.
  Future<void> updateProfileFields({
    String? username,
    String? displayName,
  }) async {
    final current = state.value;
    if (current == null) return;

    final newUsername = username != current.username ? username : null;
    final newDisplayName = displayName != current.displayName
        ? displayName
        : null;
    if (newUsername == null && newDisplayName == null) return;

    state = const AsyncLoading<Profile>();
    final repository = ref.read(profileRepositoryProvider);
    try {
      if (newUsername != null) await repository.updateUsername(newUsername);
      if (newDisplayName != null) {
        await repository.updateDisplayName(newDisplayName);
      }
      await _reload(current);
    } catch (_) {
      // Re-read rather than blindly reverting: with two writes, the first may
      // have committed before the second failed, so restoring the old value
      // would misreport what the server holds.
      await _restore(current);
      rethrow;
    }
  }

  /// Re-reads the profile and republishes the identity cache entry for it.
  Future<void> _reload(Profile previous) async {
    state = AsyncData(await ref.read(profileRepositoryProvider).getProfile());
    ref.invalidate(playerInfoCacheProvider(id: previous.id));
  }

  /// Best-effort resync after a failed mutation, falling back to what was on
  /// screen if even the re-read fails.
  Future<void> _restore(Profile previous) async {
    try {
      await _reload(previous);
    } catch (_) {
      state = AsyncData(previous);
    }
  }
}
