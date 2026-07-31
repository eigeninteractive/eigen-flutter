import 'package:eigen_flutter/core/notifications/firebase_messaging_registration.dart';
import 'package:eigen_flutter/core/notifications/firebase_messaging_registration_native.dart'
    if (dart.library.js_interop) 'package:eigen_flutter/core/notifications/firebase_messaging_registration_web.dart'
    as implementation;
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Creates the FCM registration adapter for the current platform.
FirebaseMessagingRegistration createFirebaseMessagingRegistration(
  FirebaseMessaging messaging,
  FirebaseInstallations installations,
) => implementation.createFirebaseMessagingRegistration(
  messaging,
  installations,
);
