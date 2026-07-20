# eigen_sdk

The pure-Dart transport SDK for the [Eigen server](https://github.com/seenu-k/eigen-server).
No Flutter dependency.

It owns everything the client needs to talk to the server:

- the **REST client** and models, generated from the server's `openapi.json`;
- the hand-written **WebSocket frame stream** (version-ordered frames, gap
  recovery, reconnect resync);
- a typed **error envelope** (`{ error, code? }` → `EngineException`).

Authentication is **injected** — the SDK takes a token provider
(`Future<String> Function()`) that the host app fills from Firebase; the SDK
itself has no auth dependency.

This is a private workspace member of the `eigen-flutter` repo (the Flutter
shell `eigen_flutter` depends on it by path). It is not published to pub.dev.
