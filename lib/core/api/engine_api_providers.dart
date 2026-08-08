import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/auth_interceptor.dart';
import 'package:eigen_flutter/core/api/game_socket.dart';
import 'package:eigen_flutter/core/api/retry_policy.dart';
import 'package:eigen_flutter/core/api/server_clock.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'engine_api_providers.g.dart';

/// The app-wide HTTP client for the engine: the data layer's single backend
/// handle.
///
/// Only repositories and data services may watch this or the API providers
/// below; everything above them consumes domain types. Enforced by
/// `test/core/architecture/api_isolation_test.dart`.
///
/// The base URL is the origin only: every generated route already carries its
/// `/api/engine` prefix.
///
/// The generated `EigenApi` facade is deliberately not used, but not because it
/// can't take this Dio. It can (`EigenApi(dio: ..., interceptors: const [])`
/// installs none of its own). The reason is the split below: each repository
/// depends on the one narrow `*Api` it needs, so a fake in a test is that one
/// resource, not the whole surface. The facade would hand every repository all
/// of them.
@Riverpod(keepAlive: true)
Dio engineDio(Ref ref) {
  final config = ref.watch(appConfigProvider).engine;
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  dio.interceptors.add(AuthInterceptor(FirebaseAuth.instance));
  dio.interceptors.add(ref.watch(serverClockProvider).interceptor);
  // Transport-level retry, idempotent reads only. Retries a GET whose failure
  // carried no response (a dropped connection or a timeout, where the outcome
  // is unknown) twice with short backoff. A write is never retried (a
  // timed-out POST may have landed on the server), and any failure that carried
  // a response is the server's decision, left untouched for `engineCall` to map
  // (a 429 included; its Retry-After is respected, not auto-retried). The
  // retry replays the whole interceptor chain, so `AuthInterceptor` re-attaches
  // a fresh token each attempt; added last so it is the outermost handler.
  dio.interceptors.add(
    RetryInterceptor(
      dio: dio,
      retries: 2,
      retryDelays: const [
        Duration(milliseconds: 200),
        Duration(milliseconds: 400),
      ],
      retryEvaluator: retryTransientGet,
    ),
  );
  ref.onDispose(dio.close);
  return dio;
}

/// Server time, tracked from the `Date` header of every engine response.
///
/// Deadlines on the wire are absolute server timestamps, so every countdown in
/// the app measures against this rather than the device clock.
@Riverpod(keepAlive: true)
ServerClock serverClock(Ref ref) => ServerClock();

/// Games, the lobby, and the frame history: the whole play surface.
@Riverpod(keepAlive: true)
GamesApi gamesApi(Ref ref) => GamesApi(ref.watch(engineDioProvider));

/// Friends, friend requests, user search, and friends' open games.
@Riverpod(keepAlive: true)
SocialApi socialApi(Ref ref) => SocialApi(ref.watch(engineDioProvider));

/// The caller's own profile, ratings, devices, username, and account deletion.
@Riverpod(keepAlive: true)
MeApi meApi(Ref ref) => MeApi(ref.watch(engineDioProvider));

/// Batch identity lookup for rendering other players.
@Riverpod(keepAlive: true)
PlayersApi playersApi(Ref ref) => PlayersApi(ref.watch(engineDioProvider));

/// The bot catalog offered when creating a solo game.
@Riverpod(keepAlive: true)
BotsApi botsApi(Ref ref) => BotsApi(ref.watch(engineDioProvider));

/// Opens per-game frame sockets.
///
/// Stateless and shared: one instance dials as many games as the session needs,
/// and each `connect` owns its own connection and reconnect loop.
@Riverpod(keepAlive: true)
GameSocket gameSocket(Ref ref) => GameSocket(
  baseUrl: ref.watch(appConfigProvider).engine.apiBaseUrl,
  auth: FirebaseAuth.instance,
);
