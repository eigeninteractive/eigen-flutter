/// The Eigen client SDK — pure-Dart transport to the Eigen server.
///
/// Wraps the generated REST client and the hand-written frame-stream socket
/// behind a Flutter-agnostic surface. Authentication is injected: the SDK never
/// depends on Firebase, only on a token provider supplied by the host app.
///
/// The public surface is filled in as the transport layers land (Stage 1: the
/// generated REST client + error envelope; then the socket layer).
library;
