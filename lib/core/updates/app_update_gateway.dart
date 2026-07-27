import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

import 'browser_reload.dart';

/// Native update state normalized across the platform plugin and app shell.
enum NativeUpdateAvailability { none, immediate, flexible, flexibleDownloaded }

/// Result of asking the operating system to begin an update.
enum NativeUpdateAttempt { success, declined, failed }

/// Update mechanism available to this build.
enum ClientUpdatePlatform { androidPlay, web, unsupported }

/// Testable boundary around Play in-app updates and browser reload.
abstract interface class AppUpdateGateway {
  ClientUpdatePlatform get platform;

  Future<NativeUpdateAvailability> checkForUpdate();
  Future<NativeUpdateAttempt> performImmediateUpdate();
  Future<NativeUpdateAttempt> startFlexibleUpdate();
  Future<void> completeFlexibleUpdate();
  Future<void> reloadWeb();
}

/// Plugin-backed update gateway used by production apps.
class PluginAppUpdateGateway implements AppUpdateGateway {
  const PluginAppUpdateGateway();

  @override
  ClientUpdatePlatform get platform {
    if (kIsWeb) return ClientUpdatePlatform.web;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return ClientUpdatePlatform.androidPlay;
    }
    return ClientUpdatePlatform.unsupported;
  }

  @override
  Future<NativeUpdateAvailability> checkForUpdate() async {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability ==
            UpdateAvailability.developerTriggeredUpdateInProgress &&
        info.installStatus == InstallStatus.downloaded) {
      return NativeUpdateAvailability.flexibleDownloaded;
    }
    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      return NativeUpdateAvailability.none;
    }
    if (info.immediateUpdateAllowed) {
      return NativeUpdateAvailability.immediate;
    }
    if (info.flexibleUpdateAllowed) {
      return NativeUpdateAvailability.flexible;
    }
    return NativeUpdateAvailability.none;
  }

  @override
  Future<NativeUpdateAttempt> performImmediateUpdate() async {
    final result = await InAppUpdate.performImmediateUpdate();
    return _attempt(result);
  }

  @override
  Future<NativeUpdateAttempt> startFlexibleUpdate() async {
    final result = await InAppUpdate.startFlexibleUpdate();
    return _attempt(result);
  }

  @override
  Future<void> completeFlexibleUpdate() => InAppUpdate.completeFlexibleUpdate();

  @override
  Future<void> reloadWeb() async => reloadBrowser();
}

NativeUpdateAttempt _attempt(AppUpdateResult result) => switch (result) {
  AppUpdateResult.success => NativeUpdateAttempt.success,
  AppUpdateResult.userDeniedUpdate => NativeUpdateAttempt.declined,
  AppUpdateResult.inAppUpdateFailed => NativeUpdateAttempt.failed,
};
