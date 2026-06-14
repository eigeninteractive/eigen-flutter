import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages uploading user avatar images to Supabase Storage.
class AvatarStorageService {
  AvatarStorageService(this._client);

  final SupabaseClient _client;

  static const _bucket = 'avatars';

  /// Uploads [bytes] to the avatars bucket at path [userId], replacing any
  /// existing avatar.
  ///
  /// Returns the public URL with a `?v=<timestamp>` cache-buster so that
  /// [CachedNetworkImage] and any CDN in front of Supabase treat each upload
  /// as a distinct resource. Without this, the URL is identical before and
  /// after an upload, causing both on-device and CDN caches to serve the
  /// old image until their TTL expires.
  ///
  /// A 1-year [cacheControl] is set because the URL is already unique per
  /// upload — long edge-node caching is safe and improves delivery performance.
  Future<String> uploadAvatar(
    String userId,
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) async {
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          userId,
          bytes,
          fileOptions: FileOptions(
            contentType: mimeType,
            upsert: true,
            cacheControl: '31536000',
          ),
        );

    final baseUrl = _client.storage.from(_bucket).getPublicUrl(userId);
    return '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}
