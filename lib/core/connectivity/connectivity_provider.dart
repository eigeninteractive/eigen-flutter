import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_provider.g.dart';

/// Emits the current connectivity state whenever the network changes.
///
/// Note: reflects network interface availability, not necessarily internet
/// reachability (e.g. a connected Wi-Fi with no route to the internet will
/// not report [ConnectivityResult.none]).
@riverpod
Stream<List<ConnectivityResult>> connectivity(Ref ref) =>
    Connectivity().onConnectivityChanged;

/// True when every connectivity result is [ConnectivityResult.none].
///
/// Returns false during the brief loading window before the first event.
@riverpod
bool isOffline(Ref ref) {
  final results = ref.watch(connectivityProvider).whenOrNull(data: (v) => v);
  if (results == null) return false;
  return results.isNotEmpty &&
      results.every((r) => r == ConnectivityResult.none);
}
