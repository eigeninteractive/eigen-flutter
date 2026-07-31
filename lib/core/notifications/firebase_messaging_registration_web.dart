@JS('firebase_messaging')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:eigen_flutter/core/notifications/firebase_messaging_registration.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@JS('getMessaging')
external _Messaging _getMessaging();

@JS('register')
external JSPromise<JSAny?> _registerWithFcm(
  _Messaging messaging,
  _RegisterOptions options,
);

@JS('onRegistered')
external JSFunction _onRegistered(_Messaging messaging, JSFunction callback);

@JS('onUnregistered')
external JSFunction _onUnregistered(_Messaging messaging, JSFunction callback);

extension type _Messaging._(JSObject _) implements JSObject {}

extension type _RegisterOptions._(JSObject _) implements JSObject {
  external factory _RegisterOptions({JSString vapidKey});
}

FirebaseMessagingRegistration createFirebaseMessagingRegistration(
  FirebaseMessaging messaging,
  FirebaseInstallations installations,
) => _WebFirebaseMessagingRegistration();

final class _WebFirebaseMessagingRegistration
    implements FirebaseMessagingRegistration {
  _WebFirebaseMessagingRegistration() {
    final messaging = _getMessaging();
    _onRegistered(
      messaging,
      (JSString fid) {
        _registeredFids.add(fid.toDart);
      }.toJS,
    );
    _onUnregistered(
      messaging,
      (JSString fid) {
        _unregisteredFids.add(fid.toDart);
      }.toJS,
    );
  }

  final _registeredFids = StreamController<String>.broadcast(sync: true);
  final _unregisteredFids = StreamController<String>.broadcast(sync: true);

  @override
  Stream<String> get registeredFids => _registeredFids.stream;

  @override
  Stream<String> get unregisteredFids => _unregisteredFids.stream;

  @override
  Future<String?> register({required String vapidKey}) async {
    await _registerWithFcm(
      _getMessaging(),
      _RegisterOptions(vapidKey: vapidKey.toJS),
    ).toDart;
    return null;
  }
}
