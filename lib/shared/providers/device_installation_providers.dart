import 'package:eigen_flutter/core/api/engine_api_providers.dart';
import 'package:eigen_flutter/shared/data/device_installation_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_installation_providers.g.dart';

/// Singleton [DeviceInstallationRepository] instance.
@Riverpod(keepAlive: true)
DeviceInstallationRepository deviceInstallationRepository(Ref ref) {
  return DeviceInstallationRepository(ref.watch(meApiProvider));
}
