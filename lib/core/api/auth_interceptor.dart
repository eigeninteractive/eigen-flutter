import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Attaches the signed-in user's Firebase ID token to every engine request.
///
/// The token is read per request rather than cached here: `getIdToken()`
/// returns the SDK's cached token and transparently refreshes it when it is
/// close to expiry, so this stays cheap while never sending a stale token.
///
/// A signed-out caller sends no header at all and the server answers 401. That
/// is deliberate: the engine has no anonymous surface, and a missing token is
/// the same failure as a bad one.
///
/// There is no refresh-and-retry on 401. The transport `RetryInterceptor`
/// retries only idempotent GETs whose failure carried no response, so a 401 (a
/// response, and on a request of any method) is never retried; and because
/// `getIdToken()` already refreshes ahead of expiry, a 401 here means the
/// session is genuinely gone, which the auth layer handles by signing the user
/// out, not something a retry would fix.
class AuthInterceptor extends Interceptor {
  const AuthInterceptor(this._auth);

  final FirebaseAuth _auth;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
