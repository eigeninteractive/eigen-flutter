import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eigen_flutter/core/api/engine_call.dart';

/// Uploads the signed-in user's avatar.
///
/// Not part of the generated client: a raw binary body has no clean OpenAPI
/// representation, so this is the one place that builds a request by hand. It
/// still goes through [engineData], so a rejection surfaces as the same
/// `EngineException` - with [ErrorCode.imageTooLarge] or
/// [ErrorCode.unsupportedImageType] - that every other call produces.
///
/// R2 has no client-direct writes and no row-level security, so the image is
/// streamed through the worker rather than uploaded from the device.
class AvatarStorageService {
  AvatarStorageService(this._dio);

  final Dio _dio;

  /// Image types the server accepts.
  static const allowedMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

  /// Replaces the caller's avatar with [bytes] and returns its new URL.
  ///
  /// The returned URL may be relative - run it through `resolveAvatarUrl`
  /// before handing it to an image widget. It carries a `?v=` cache-buster the
  /// server bumps per upload, because the underlying object is overwritten in
  /// place and the URL would otherwise be unchanged.
  ///
  /// The server also writes the new URL onto the user's profile, so a cached
  /// profile should be invalidated after this rather than patched locally.
  Future<String> uploadAvatar(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final body = await engineData(
      () => _dio.put<Map<String, dynamic>>(
        '/api/engine/me/avatar',
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            Headers.contentTypeHeader: mimeType,
            Headers.contentLengthHeader: bytes.length,
          },
        ),
      ),
    );
    return body['avatarUrl'] as String;
  }
}
