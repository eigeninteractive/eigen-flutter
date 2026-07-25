// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Application-wide [FirebaseNotificationService] instance.

@ProviderFor(notificationService)
final notificationServiceProvider = NotificationServiceProvider._();

/// Application-wide [FirebaseNotificationService] instance.

final class NotificationServiceProvider
    extends
        $FunctionalProvider<
          FirebaseNotificationService,
          FirebaseNotificationService,
          FirebaseNotificationService
        >
    with $Provider<FirebaseNotificationService> {
  /// Application-wide [FirebaseNotificationService] instance.
  NotificationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationServiceHash();

  @$internal
  @override
  $ProviderElement<FirebaseNotificationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FirebaseNotificationService create(Ref ref) {
    return notificationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FirebaseNotificationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FirebaseNotificationService>(value),
    );
  }
}

String _$notificationServiceHash() =>
    r'0a59809050d48ef9de99e5d185e98551455d442b';

/// Current notification permission status.
///
/// Auto-disposes so it is re-fetched on demand. Invalidate this provider
/// in [AppLifecycleListener.onResume] so the Settings screen reflects any
/// changes the user made in system Settings while the app was backgrounded.

@ProviderFor(notificationPermissionStatus)
final notificationPermissionStatusProvider =
    NotificationPermissionStatusProvider._();

/// Current notification permission status.
///
/// Auto-disposes so it is re-fetched on demand. Invalidate this provider
/// in [AppLifecycleListener.onResume] so the Settings screen reflects any
/// changes the user made in system Settings while the app was backgrounded.

final class NotificationPermissionStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<AuthorizationStatus>,
          AuthorizationStatus,
          FutureOr<AuthorizationStatus>
        >
    with
        $FutureModifier<AuthorizationStatus>,
        $FutureProvider<AuthorizationStatus> {
  /// Current notification permission status.
  ///
  /// Auto-disposes so it is re-fetched on demand. Invalidate this provider
  /// in [AppLifecycleListener.onResume] so the Settings screen reflects any
  /// changes the user made in system Settings while the app was backgrounded.
  NotificationPermissionStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationPermissionStatusProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationPermissionStatusHash();

  @$internal
  @override
  $FutureProviderElement<AuthorizationStatus> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AuthorizationStatus> create(Ref ref) {
    return notificationPermissionStatus(ref);
  }
}

String _$notificationPermissionStatusHash() =>
    r'06f8156292d039d50f4922bbf8aa6f8c315ac9d6';
