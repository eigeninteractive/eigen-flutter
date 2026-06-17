import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:riverpod_annotation/experimental/json_persist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_engine/core/storage/storage_provider.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/profile/data/avatar_storage_service.dart';
import 'package:eigen_engine/features/profile/data/models/user_profile.dart';
import 'package:eigen_engine/features/profile/data/profile_repository.dart';
import 'package:eigen_engine/shared/providers/player_providers.dart';

part 'profile_providers.g.dart';

/// Provider for ProfileRepository instance.
@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return ProfileRepository(supabase);
}

/// Provider for AvatarStorageService instance.
@Riverpod(keepAlive: true)
AvatarStorageService avatarStorageService(Ref ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return AvatarStorageService(supabase);
}

/// Provider for current user's profile data.
///
/// Kept alive and persisted to SQLite so the profile loads from cache
/// on cold start (no spinner). The network fetch runs in the background
/// and silently refreshes state when it completes.
@Riverpod(keepAlive: true)
@JsonPersist()
class CurrentUserProfile extends _$CurrentUserProfile {
  @override
  Future<UserProfile> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      throw StateError('User not authenticated');
    }

    // Stale-while-revalidate: SQLite cache races the network fetch.
    // Cache (~5ms) typically wins first, eliminating the cold-start spinner.
    // Network result overwrites silently; if network wins first, stale
    // cache is discarded automatically via didChange guard in persist().
    persist(
      ref.watch(storageProvider.future),
      key: profileCacheKey(user.id),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        // Cache-schema version for the persisted UserProfile. Bump when this
        // model's JSON shape changes breakingly — stale rows are then discarded
        // on next launch (a decode failure is already a safe cache-miss). It is
        // per-provider, so bumping it doesn't disturb other caches. See
        // docs/backward-compatibility.md.
        destroyKey: '1',
      ),
    );

    final repository = ref.watch(profileRepositoryProvider);
    return repository.getUserProfile(user.id);
  }

  /// Refreshes the profile from the database.
  void refresh() {
    ref.invalidateSelf();
    future.ignore();
  }

  /// Uploads [bytes] as the user's new avatar and updates the profile.
  ///
  /// Stores the storage path in the DB; a signed URL is generated at read
  /// time by [ProfileRepository.getUserProfile].
  Future<void> uploadAvatar(Uint8List bytes) async {
    final currentProfile = state.value;
    if (currentProfile == null) return;

    // Evict old avatar from local image caches before uploading. The new upload
    // gets a fresh ?v=timestamp URL so the old entry is never requested again,
    // but evicting here reclaims disk/memory immediately rather than waiting
    // for LRU expiry.
    final oldUrl = currentProfile.avatarUrl;
    if (oldUrl != null) await CachedNetworkImageProvider(oldUrl).evict();

    state = const AsyncLoading<UserProfile>();

    final repository = ref.read(profileRepositoryProvider);
    final storageService = ref.read(avatarStorageServiceProvider);

    try {
      final path = await storageService.uploadAvatar(currentProfile.id, bytes);
      final updatedProfile = await repository.updateProfile(
        currentProfile.id,
        avatarUrl: path,
      );
      state = AsyncData(updatedProfile);
      ref.invalidate(playerInfoCacheProvider(id: currentProfile.id));
    } catch (e) {
      try {
        final refreshed = await repository.getUserProfile(currentProfile.id);
        state = AsyncData(refreshed);
      } catch (_) {
        state = AsyncData(currentProfile);
      }
      rethrow;
    }
  }

  /// Updates the profile with new values in a single operation.
  ///
  /// Sets loading state during save, then refreshes from server.
  /// Only updates fields that differ from current values.
  Future<void> updateProfileFields({
    String? username,
    String? displayName,
    String? avatarUrl,
  }) async {
    final currentProfile = state.value;
    if (currentProfile == null) return;

    // Determine what actually changed
    final usernameChanged =
        username != null && username != currentProfile.username;
    final displayNameChanged =
        displayName != null && displayName != currentProfile.displayName;
    final avatarChanged =
        avatarUrl != null && avatarUrl != currentProfile.avatarUrl;

    if (!usernameChanged && !displayNameChanged && !avatarChanged) return;

    // Set loading state
    state = const AsyncLoading<UserProfile>();

    final repository = ref.read(profileRepositoryProvider);
    try {
      // Update username via RPC (has uniqueness constraint)
      if (usernameChanged) {
        await repository.updateUsername(username);
      }

      // Update profile fields (display name, avatar).
      // updateProfile re-fetches internally, so use its return value directly.
      final UserProfile updatedProfile;
      if (displayNameChanged || avatarChanged) {
        updatedProfile = await repository.updateProfile(
          currentProfile.id,
          displayName: displayNameChanged ? displayName : null,
          avatarUrl: avatarChanged ? avatarUrl : null,
        );
      } else {
        // Only username changed — fetch updated profile.
        updatedProfile = await repository.getUserProfile(currentProfile.id);
      }
      state = AsyncData(updatedProfile);
      ref.invalidate(playerInfoCacheProvider(id: currentProfile.id));
    } catch (e) {
      // Re-fetch server state rather than blindly reverting — a partial update
      // (e.g. username succeeded, display name RPC failed) may have already
      // committed, so reverting to currentProfile would lie about server state.
      try {
        final refreshed = await repository.getUserProfile(currentProfile.id);
        state = AsyncData(refreshed);
      } catch (_) {
        state = AsyncData(currentProfile);
      }
      rethrow;
    }
  }
}
