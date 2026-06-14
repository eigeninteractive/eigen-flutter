import 'dart:developer' as developer;
import 'dart:io';

import 'package:in_app_update/in_app_update.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:eigen_engine/core/navigation/providers/navigation_providers.dart';

part 'update_notifier.g.dart';

/// Whether a downloaded flexible update is ready to install.
enum UpdateInstallStatus { idle, downloadComplete }

/// Drives the Play Store in-app update lifecycle (Android only).
///
/// Call [checkForUpdate] on each app resume. When [state] transitions to
/// [UpdateInstallStatus.downloadComplete], show the user a prompt and call
/// [completeUpdate] on confirmation.
@Riverpod(keepAlive: true)
class UpdateNotifier extends _$UpdateNotifier {
  @override
  UpdateInstallStatus build() => UpdateInstallStatus.idle;

  /// Checks for an available update and starts the appropriate flow.
  Future<void> checkForUpdate() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();

      // Flexible update downloaded in a previous session — ready to install.
      if (info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress &&
          info.installStatus == InstallStatus.downloaded) {
        state = UpdateInstallStatus.downloadComplete;
        return;
      }

      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;

      if (info.immediateUpdateAllowed) {
        // Skip while a game is active — retry on the next resume.
        // Immediate updates take priority over flexible; never downgrade.
        if (!_isGameActive()) await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) {
          state = UpdateInstallStatus.downloadComplete;
        }
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
      await InAppUpdate.completeFlexibleUpdate();
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
