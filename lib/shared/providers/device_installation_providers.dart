import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_flutter/shared/data/device_installation_repository.dart';
import 'package:eigen_flutter/shared/providers/supabase_client_provider.dart';

part 'device_installation_providers.g.dart';

/// Singleton [DeviceInstallationRepository] instance.
@Riverpod(keepAlive: true)
DeviceInstallationRepository deviceInstallationRepository(Ref ref) {
  return DeviceInstallationRepository(ref.watch(supabaseClientProvider));
}
