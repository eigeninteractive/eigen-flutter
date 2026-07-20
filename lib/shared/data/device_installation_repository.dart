import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eigen_flutter/shared/data/db_guard.dart';

/// Repository for the `device_installations` push-registration rows.
///
/// One row per (user, Firebase installation id); the server targets pushes at
/// the FID. The notification service owns when to register/unregister — this
/// class only owns how the rows are written.
class DeviceInstallationRepository {
  DeviceInstallationRepository(this._client);

  final SupabaseClient _client;

  /// Upserts the current user's registration for [fid] on [platform]
  /// (`ios`, `android`, or `web`).
  Future<void> upsert({required String fid, required String platform}) =>
      dbGuard(
        () => _client.rpc(
          'app_upsert_device_installation',
          params: {'p_fid': fid, 'p_platform': platform},
        ),
      );

  /// Deletes the current user's registration row for [fid] so the server
  /// stops targeting this install.
  Future<void> delete({required String fid}) => dbGuard(
    () => _client.rpc('app_delete_device_installation', params: {'p_fid': fid}),
  );
}
