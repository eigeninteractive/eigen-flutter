import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/engine_call.dart';
import 'package:flutter/foundation.dart';

/// The current user's push registrations: one per Firebase installation id.
///
/// Pushes are targeted at the FID, so the server needs the FID for every
/// install the user is signed in on. The notification service owns *when* to
/// register and unregister; this class only owns how it is written.
class DeviceInstallationRepository {
  DeviceInstallationRepository(this._api);

  final MeApi _api;

  /// Registers (or refreshes) this install for the signed-in user.
  ///
  /// Idempotent: re-registering the same FID is the normal case on every
  /// launch. The platform is a property of the running build rather than of the
  /// call, so it is resolved here and callers never name it.
  Future<void> upsert({required String fid}) => engineCall(
    () => _api.registerDevice(
      deviceRegistration: DeviceRegistration(fid: fid, platform: _platform),
    ),
  );

  /// This build's platform in the server's vocabulary.
  ///
  /// macOS registers as `ios`: it shares the APNs delivery path, and the server
  /// only distinguishes platforms to pick a push transport.
  static DeviceRegistrationPlatformEnum get _platform {
    if (kIsWeb) return DeviceRegistrationPlatformEnum.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS => DeviceRegistrationPlatformEnum.ios,
      TargetPlatform.android => DeviceRegistrationPlatformEnum.android,
      _ => throw UnsupportedError(
        'Push notifications are not supported on $defaultTargetPlatform',
      ),
    };
  }

  /// Drops this install's registration so the server stops targeting it.
  ///
  /// Idempotent: unregistering an FID the server never knew about succeeds.
  Future<void> delete({required String fid}) =>
      engineCall(() => _api.unregisterDevice(fid: fid));
}
