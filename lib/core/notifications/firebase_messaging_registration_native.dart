import 'package:eigen_flutter/core/notifications/firebase_messaging_registration.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

FirebaseMessagingRegistration createFirebaseMessagingRegistration(
  FirebaseMessaging messaging,
  FirebaseInstallations installations,
) => _NativeFirebaseMessagingRegistration(messaging, installations);

final class _NativeFirebaseMessagingRegistration
    implements FirebaseMessagingRegistration {
  const _NativeFirebaseMessagingRegistration(
    this._messaging,
    this._installations,
  );

  final FirebaseMessaging _messaging;
  final FirebaseInstallations _installations;

  @override
  Stream<String> get registeredFids => const Stream.empty();

  @override
  Stream<String> get unregisteredFids => const Stream.empty();

  @override
  Future<String> register({required String vapidKey}) async {
    await _messaging.setAutoInitEnabled(true);
    return _installations.getId();
  }
}
