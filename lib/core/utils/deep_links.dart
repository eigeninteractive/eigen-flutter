/// Returns a shareable invite link for the given join [code], or `null` if
/// [appHost] is not configured.
///
/// Produces a URL such as `https://strategy.eigeninteractive.com/join/ABC123`
/// that opens the app directly on devices where it is installed, or shows
/// the fallback landing page otherwise.
///
/// [appHost] comes from `EngineConfig.appHost` and must match the domain
/// declared in `AndroidManifest.xml` and `Runner.entitlements`.
Uri? gameInviteLink(String code, {required String? appHost}) =>
    appHost != null ? Uri.https(appHost, '/join/$code') : null;

/// Returns a shareable link to replay the finished game with [gameId], or
/// `null` if [appHost] is not configured.
///
/// Produces a URL such as `https://strategy.eigeninteractive.com/game/<id>`
/// that opens the game on the recipient's device. A recipient who did not play
/// in the game lands on its replay entry; only meaningful for public games,
/// since the server refuses a non-participant's replay of a private one.
Uri? gameReplayLink(String gameId, {required String? appHost}) =>
    appHost != null ? Uri.https(appHost, '/game/$gameId') : null;

/// Returns a URL for the given legal [path] on the game's own host, or `null`
/// if [appHost] is not configured.
///
/// The server serves `/terms`, `/privacy` and `/delete-account` on the same
/// host as the app's deep links. That is safe because the app's App Links
/// intent-filter is scoped to the `/join` and `/game` prefixes (see the
/// [deep-link guide](https://eigeninteractive.com/docs/ship-it/deep-links)), so
/// legal paths are never intercepted and open in the browser. Opened with
/// `LaunchMode.inAppBrowserView` as belt and braces.
Uri? legalPageUrl(String path, {required String? appHost}) =>
    appHost != null ? Uri.https(appHost, path) : null;
