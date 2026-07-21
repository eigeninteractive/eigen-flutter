import 'package:dio/dio.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/auth_interceptor.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'engine_api_providers.g.dart';

/// The app-wide HTTP client for the engine — the data layer's single backend
/// handle, and the successor to the Supabase-era `supabaseClientProvider`.
///
/// Only repositories and data services may watch this or the API providers
/// below; everything above them consumes domain types. Enforced by
/// `test/core/architecture/api_isolation_test.dart`.
///
/// The base URL is the origin only: every generated route already carries its
/// `/api/engine` prefix.
///
/// The generated `EigenApi` facade is deliberately not used. It authenticates
/// by storing a fixed bearer token (`setBearerAuth`), which cannot work for
/// Firebase ID tokens that rotate roughly hourly, and it installs three further
/// auth interceptors (OAuth, basic, API key) the engine never uses.
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
  ref.onDispose(dio.close);
  return dio;
}

/// Games, the lobby, and the frame history — the whole play surface.
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
