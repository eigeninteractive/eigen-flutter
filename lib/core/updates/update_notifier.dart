import 'dart:developer' as developer;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_flutter/core/navigation/providers/navigation_providers.dart';
import 'package:eigen_flutter/core/updates/app_update_gateway.dart';

part 'update_notifier.g.dart';

/// Whether a downloaded flexible update is ready to install.
enum UpdateInstallStatus { idle, downloadComplete }

/// Outcome of an update explicitly requested from compatibility-blocked UI.
enum RequiredUpdateResult { started, declined, unavailable, failed }

/// Platform update gateway.
@Riverpod(keepAlive: true)
AppUpdateGateway appUpdateGateway(Ref ref) => const PluginAppUpdateGateway();

/// Drives background update checks and explicit compatibility updates.
///
/// Call [checkForUpdate] on each app resume. When [state] transitions to
/// [UpdateInstallStatus.downloadComplete], show the user a prompt and call
/// [completeUpdate] on confirmation.
@Riverpod(keepAlive: true)
class UpdateNotifier extends _$UpdateNotifier {
  Future<void>? _backgroundCheck;

  @override
  UpdateInstallStatus build() => UpdateInstallStatus.idle;

  /// Checks for an available Android update without interrupting active play.
  Future<void> checkForUpdate() => _backgroundCheck ??= _checkForUpdate()
      .whenComplete(() => _backgroundCheck = null);

  Future<void> _checkForUpdate() async {
    final gateway = ref.read(appUpdateGatewayProvider);
    if (gateway.platform != ClientUpdatePlatform.androidPlay) return;
    try {
      switch (await gateway.checkForUpdate()) {
        case NativeUpdateAvailability.none:
          return;
        case NativeUpdateAvailability.flexibleDownloaded:
          state = UpdateInstallStatus.downloadComplete;
          return;
        case NativeUpdateAvailability.immediate:
          // A background check must not interrupt active play. Compatibility-
          // blocked UI uses requestRequiredUpdate(), which bypasses this guard.
          if (!_isGameActive()) await gateway.performImmediateUpdate();
          return;
        case NativeUpdateAvailability.flexible:
          final result = await gateway.startFlexibleUpdate();
          if (result == NativeUpdateAttempt.success) {
            state = UpdateInstallStatus.downloadComplete;
          }
          return;
      }
    } catch (e, stack) {
      developer.log(
        'In-app update check failed',
        name: 'app.update',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Starts the strongest available update flow from update-required UI.
  ///
  /// Unlike a background check, this may launch an immediate update while the
  /// user is on a game route: the game is already blocked as incompatible.
  Future<RequiredUpdateResult> requestRequiredUpdate() async {
    final gateway = ref.read(appUpdateGatewayProvider);
    try {
      return await switch (gateway.platform) {
        ClientUpdatePlatform.androidPlay => _requestNativeUpdate(gateway),
        ClientUpdatePlatform.web => _reloadWeb(gateway),
        ClientUpdatePlatform.unsupported => Future.value(
          RequiredUpdateResult.unavailable,
        ),
      };
    } catch (e, stack) {
      developer.log(
        'Required update request failed',
        name: 'app.update',
        error: e,
        stackTrace: stack,
      );
      return RequiredUpdateResult.failed;
    }
  }

  Future<RequiredUpdateResult> _requestNativeUpdate(
    AppUpdateGateway gateway,
  ) async {
    switch (await gateway.checkForUpdate()) {
      case NativeUpdateAvailability.none:
        return RequiredUpdateResult.unavailable;
      case NativeUpdateAvailability.flexibleDownloaded:
        await gateway.completeFlexibleUpdate();
        return RequiredUpdateResult.started;
      case NativeUpdateAvailability.immediate:
        return _requiredResult(await gateway.performImmediateUpdate());
      case NativeUpdateAvailability.flexible:
        final attempt = await gateway.startFlexibleUpdate();
        if (attempt == NativeUpdateAttempt.success) {
          await gateway.completeFlexibleUpdate();
        }
        return _requiredResult(attempt);
    }
  }

  Future<RequiredUpdateResult> _reloadWeb(AppUpdateGateway gateway) async {
    await gateway.reloadWeb();
    return RequiredUpdateResult.started;
  }

  bool _isGameActive() {
    final uri = ref
        .read(goRouterProvider)
        .routerDelegate
        .currentConfiguration
        .uri;
    return uri.path.startsWith('/game/');
  }

  /// Installs a downloaded flexible update, restarting the app.
  Future<void> completeUpdate() async {
    try {
      await ref.read(appUpdateGatewayProvider).completeFlexibleUpdate();
      state = UpdateInstallStatus.idle;
    } catch (e, stack) {
      developer.log(
        'Flexible update completion failed',
        name: 'app.update',
        error: e,
        stackTrace: stack,
      );
    }
  }
}

RequiredUpdateResult _requiredResult(NativeUpdateAttempt result) =>
    switch (result) {
      NativeUpdateAttempt.success => RequiredUpdateResult.started,
      NativeUpdateAttempt.declined => RequiredUpdateResult.declined,
      NativeUpdateAttempt.failed => RequiredUpdateResult.failed,
    };
