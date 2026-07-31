/// Platform adapter for registering this Firebase installation with FCM.
///
/// FlutterFire has not yet exposed Firebase's FID registration API. Keeping
/// that compatibility seam here lets the notification service remain
/// FID-native and makes the adapter removable when FlutterFire catches up.
abstract interface class FirebaseMessagingRegistration {
  /// FIDs reported by FCM after registration or subscription repair.
  Stream<String> get registeredFids;

  /// FIDs that FCM has unregistered and the server should stop targeting.
  Stream<String> get unregisteredFids;

  /// Registers the current installation with FCM.
  ///
  /// [vapidKey] is used by Web Push and ignored on native platforms.
  ///
  /// Native returns the FID that can be uploaded immediately. Web returns null
  /// because the official SDK delivers its FID asynchronously through
  /// [registeredFids].
  Future<String?> register({required String vapidKey});
}
