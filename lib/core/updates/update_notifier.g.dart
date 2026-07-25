// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Drives the Play Store in-app update lifecycle (Android only).
///
/// Call [checkForUpdate] on each app resume. When [state] transitions to
/// [UpdateInstallStatus.downloadComplete], show the user a prompt and call
/// [completeUpdate] on confirmation.

@ProviderFor(UpdateNotifier)
final updateProvider = UpdateNotifierProvider._();

/// Drives the Play Store in-app update lifecycle (Android only).
///
/// Call [checkForUpdate] on each app resume. When [state] transitions to
/// [UpdateInstallStatus.downloadComplete], show the user a prompt and call
/// [completeUpdate] on confirmation.
final class UpdateNotifierProvider
    extends $NotifierProvider<UpdateNotifier, UpdateInstallStatus> {
  /// Drives the Play Store in-app update lifecycle (Android only).
  ///
  /// Call [checkForUpdate] on each app resume. When [state] transitions to
  /// [UpdateInstallStatus.downloadComplete], show the user a prompt and call
  /// [completeUpdate] on confirmation.
  UpdateNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updateNotifierHash();

  @$internal
  @override
  UpdateNotifier create() => UpdateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UpdateInstallStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UpdateInstallStatus>(value),
    );
  }
}

String _$updateNotifierHash() => r'bc7934f3b31eecb4ee01d770ceecf95227160695';

/// Drives the Play Store in-app update lifecycle (Android only).
///
/// Call [checkForUpdate] on each app resume. When [state] transitions to
/// [UpdateInstallStatus.downloadComplete], show the user a prompt and call
/// [completeUpdate] on confirmation.

abstract class _$UpdateNotifier extends $Notifier<UpdateInstallStatus> {
  UpdateInstallStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UpdateInstallStatus, UpdateInstallStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UpdateInstallStatus, UpdateInstallStatus>,
              UpdateInstallStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
