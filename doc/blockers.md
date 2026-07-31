# Upstream blockers

This file tracks upstream limitations that require temporary compatibility
code in `eigen_flutter`. It is for engine maintainers, not game implementors.
Keep each entry until the workaround has been removed, and re-check upstream
status before acting on it.

## Flutter Android built-in Kotlin migration

**Status:** Blocked on a compatible `in_app_review` release and a project
upgrade to Flutter 3.47 or later. Last checked: 2026-07-31.

Flutter is migrating Android apps and plugins from the separately applied
Kotlin Gradle plugin to Gradle's built-in Kotlin support. The workspace
currently uses Flutter 3.44.8 and remains on Flutter's supported compatibility
path with `android.builtInKotlin=false` and `android.newDsl=false`.

The resolved Android plugin state is:

- `in_app_review` 2.0.12 still applies `kotlin-android` unconditionally. This is
  the dependency that currently prevents enabling built-in Kotlin.
- `app_settings` 8.0.3 and `firebase_analytics` 12.4.5 already conditionally
  avoid applying the legacy Kotlin plugin when built-in Kotlin is enabled.
  They do not require an upgrade for this migration at the versions currently
  resolved.
- Flutter only supports an app opting in to built-in Kotlin from Flutter 3.47.

Do not suppress the warnings by forcing built-in Kotlin on the current Flutter
SDK. That would select an unsupported configuration while
`in_app_review` is still incompatible.

### Unblock and remove

1. Wait for or contribute an `in_app_review` release that supports Flutter's
   built-in Kotlin mode.
2. Upgrade `in_app_review`. The current `^2.0.11` constraint will accept a
   compatible 2.x release; change the constraint if support first ships in a
   new major version.
3. Upgrade the development and CI Flutter SDKs to 3.47 or later.
4. Follow Flutter's app migration guide: enable built-in Kotlin, remove the
   temporary opt-out properties, and remove obsolete Kotlin plugin/version
   declarations from generated Android apps.
5. Regenerate a game with `create-eigen-game`, then run analysis, tests, and an
   Android debug and release build. The build must complete without legacy
   Kotlin plugin warnings.

Upstream references:

- [Flutter: migrate an Android app to built-in Kotlin][flutter-app-kotlin]
- [Flutter: migrate an Android plugin to built-in Kotlin][flutter-plugin-kotlin]
- [`in_app_review` on pub.dev][in-app-review]

## FlutterFire Firebase Installation ID registration API

**Status:** Blocked until FlutterFire publishes the proposed API in a released
package. [Issue #18479][flutterfire-issue] and
[PR #18482][flutterfire-pr] were both open when last checked on 2026-07-31.

The current Firebase Cloud Messaging API in the released `firebase_messaging`
package does not expose Firebase's FID-based `register`, `unregister`,
`onRegistered`, or `onUnregistered` operations. Eigen uses FIDs as the
installation identity sent to its server, so token-only FlutterFire APIs are
not an adequate replacement.

PR #18482 proposes those operations across the Dart platform interface,
Android, iOS, and web, with unit and integration coverage. A merged PR is not
enough to remove our workaround: the public API must be present in a released
`firebase_messaging` version that the package can consume.

### Current compatibility seam

Keep the workaround narrow and internal:

- [`FirebaseMessagingRegistration`][registration-adapter] is the removable
  interface used by the notification service.
- [The native implementation][native-registration] enables messaging auto-init
  and reads the current FID through `firebase_app_installations`.
- [The web implementation][web-registration] calls the official Firebase
  Messaging JavaScript `register`, `onRegistered`, and `onUnregistered` APIs
  through Dart JS interop.
- [The Android library manifest][android-manifest] enables FID registration,
  while [the plugin Gradle build][android-gradle] temporarily supplies Firebase
  BoM 34.16.0 and `firebase-messaging`.

Do not spread direct JS interop or native SDK handling into application
features. Keeping it behind this interface makes the workaround replaceable
without changing the notification service or game implementor API.

### Unblock and remove

1. Confirm the FlutterFire PR is merged and identify the first published
   `firebase_messaging` version containing the API.
2. Upgrade the compatible FlutterFire package set together.
3. Replace `FirebaseMessagingRegistration` usage with
   `FirebaseMessaging.instance.register`, `onRegistered`, and
   `onUnregistered`, and use `unregister` where Eigen explicitly opts an
   installation out.
4. Remove the adapter and its platform implementations.
5. Remove the Android manifest metadata, Firebase BoM pin, direct
   `firebase-messaging` dependency, and `firebase_app_installations` dependency
   only where the released FlutterFire implementation makes each one
   unnecessary. Verify this from its release and native dependency metadata;
   do not assume that the Dart API alone replaces build-time configuration.
6. Test Android and web registration, registration and unregistration events,
   guest-to-account upgrades, sign-out and account deletion, foreground and
   background delivery, and server-side installation reconciliation.
7. Generate and build a fresh game scaffold to confirm that implementors do not
   inherit new manual Firebase or Android configuration.

[flutter-app-kotlin]: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
[flutter-plugin-kotlin]: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
[in-app-review]: https://pub.dev/packages/in_app_review
[flutterfire-issue]: https://github.com/firebase/flutterfire/issues/18479
[flutterfire-pr]: https://github.com/firebase/flutterfire/pull/18482
[registration-adapter]: ../lib/core/notifications/firebase_messaging_registration.dart
[native-registration]: ../lib/core/notifications/firebase_messaging_registration_native.dart
[web-registration]: ../lib/core/notifications/firebase_messaging_registration_web.dart
[android-manifest]: ../android/src/main/AndroidManifest.xml
[android-gradle]: ../android/build.gradle.kts
