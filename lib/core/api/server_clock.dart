import 'package:dio/dio.dart';

/// Server time, as best the client can tell.
///
/// Every deadline on the wire is an absolute server timestamp, so rendering a
/// countdown means subtracting *server* now, not device now. A device whose
/// clock is minutes off would otherwise show a turn timer that disagrees with
/// when the turn actually expires, and the server is the authority: its alarm
/// fires on exactly the deadline it sent.
///
/// The offset comes free from the `Date` header every HTTP response carries, so
/// this needs no wire change and no extra request. Until the first response
/// lands the offset is zero, which is the right default: an unsynced device is
/// rare, and a fresh install has usually made a request before it can display a
/// clock.
///
/// Accuracy is roughly one round-trip, which is orders of magnitude finer than
/// the skew this exists to correct.
class ServerClock {
  Duration _offset = Duration.zero;

  /// How far ahead of the device the server is. Zero until a response arrives.
  Duration get offset => _offset;

  /// The current time on the server.
  DateTime now() => DateTime.now().toUtc().add(_offset);

  /// Time remaining until [deadline], an epoch-millisecond server timestamp.
  ///
  /// Clamped at zero: an expired deadline reads as "no time left" rather than
  /// as a negative duration a countdown would have to special-case. The server
  /// grants a grace period beyond this, which is deliberately invisible here:
  /// the client shows the true deadline and lets the server be lenient.
  Duration remainingUntil(int deadline) {
    final left = DateTime.fromMillisecondsSinceEpoch(
      deadline,
      isUtc: true,
    ).difference(now());
    return left.isNegative ? Duration.zero : left;
  }

  /// A server timestamp expressed on the *device* clock.
  ///
  /// Countdown widgets tick by repeatedly subtracting `DateTime.now()`, which
  /// is device time, so converting once here keeps that arithmetic correct on
  /// every tick, where handing them a raw server timestamp would bake the skew
  /// into every frame.
  DateTime deviceTimeFor(int serverEpochMs) =>
      DateTime.now().add(remainingUntil(serverEpochMs));

  /// Records the server time reported by one response.
  void _observe(DateTime serverTime) {
    _offset = serverTime.difference(DateTime.now().toUtc());
  }

  /// Keeps [ServerClock] in step with the server, from the `Date` header.
  Interceptor get interceptor => _ServerClockInterceptor(this);
}

class _ServerClockInterceptor extends Interceptor {
  _ServerClockInterceptor(this._clock);

  final ServerClock _clock;

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _sync(response.headers);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // A rejection is still a response from the server, and its clock is just
    // as good as a success's.
    final headers = err.response?.headers;
    if (headers != null) _sync(headers);
    handler.next(err);
  }

  void _sync(Headers headers) {
    final raw = headers.value('date');
    if (raw == null) return;
    final parsed = HttpDate.tryParse(raw);
    if (parsed != null) _clock._observe(parsed.toUtc());
  }
}

/// Parses the RFC 1123 dates HTTP uses.
///
/// `dart:io`'s `HttpDate` is not available on web, and this runs on both.
abstract final class HttpDate {
  static DateTime? tryParse(String value) {
    // `Sun, 06 Nov 1994 08:49:37 GMT`: the only format CF emits, and the only
    // one HTTP/1.1 requires a client to generate.
    final match = RegExp(
      r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value.trim());
    if (match == null) return null;

    final month = _months.indexOf(match.group(2)!) + 1;
    if (month == 0) return null;

    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}
