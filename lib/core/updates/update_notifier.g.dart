// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Platform update gateway.

@ProviderFor(appUpdateGateway)
final appUpdateGatewayProvider = AppUpdateGatewayProvider._();

/// Platform update gateway.

final class AppUpdateGatewayProvider
    extends
        $FunctionalProvider<
          AppUpdateGateway,
          AppUpdateGateway,
          AppUpdateGateway
        >
    with $Provider<AppUpdateGateway> {
  /// Platform update gateway.
  AppUpdateGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appUpdateGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appUpdateGatewayHash();

  @$internal
  @override
  $ProviderElement<AppUpdateGateway> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppUpdateGateway create(Ref ref) {
    return appUpdateGateway(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppUpdateGateway value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppUpdateGateway>(value),
    );
  }
}

String _$appUpdateGatewayHash() => r'fe97aec49b8ffe84a76828402ddba99d9a4d9b5a';

/// Drives background update checks and explicit compatibility updates.
///
/// Call [checkForUpdate] on each app resume. When [state] transitions to
/// [UpdateInstallStatus.downloadComplete], show the user a prompt and call
/// [completeUpdate] on confirmation.

@ProviderFor(UpdateNotifier)
final updateProvider = UpdateNotifierProvider._();

/// Drives background update checks and explicit compatibility updates.
///
/// Call [checkForUpdate] on each app resume. When [state] transitions to
/// [UpdateInstallStatus.downloadComplete], show the user a prompt and call
/// [completeUpdate] on confirmation.
final class UpdateNotifierProvider
    extends $NotifierProvider<UpdateNotifier, UpdateInstallStatus> {
  /// Drives background update checks and explicit compatibility updates.
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

String _$updateNotifierHash() => r'5f1991bbb36ba6789bda6697a074ab872e34d86b';

/// Drives background update checks and explicit compatibility updates.
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
