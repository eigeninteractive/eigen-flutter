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

/// Returns a URL for the given legal [path] on the shared root domain, or
/// `null` if [legalHost] is not configured.
///
/// Uses [legalHost] (e.g. `eigeninteractive.com`) rather than the
/// game-specific app-host subdomain so the OS never intercepts legal links as
/// deep links.
Uri? legalPageUrl(String path, {required String? legalHost}) =>
    legalHost != null ? Uri.https(legalHost, path) : null;
