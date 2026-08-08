import 'package:checks/checks.dart';
import 'package:dio/dio.dart';
import 'package:eigen_flutter/core/api/server_clock.dart';
import 'package:flutter_test/flutter_test.dart';

Response<dynamic> _responseDated(String? date) => Response<dynamic>(
  requestOptions: RequestOptions(path: '/api/engine/lobby'),
  statusCode: 200,
  headers: Headers.fromMap({
    if (date != null) 'date': [date],
  }),
);

/// Drives an interceptor's `onResponse` without a live Dio.
void _deliver(Interceptor interceptor, Response<dynamic> response) {
  interceptor.onResponse(response, ResponseInterceptorHandler());
}

void main() {
  test('parses an RFC 1123 date', () {
    check(
      HttpDate.tryParse('Sun, 06 Nov 1994 08:49:37 GMT'),
    ).equals(DateTime.utc(1994, 11, 6, 8, 49, 37));
  });

  test('rejects anything else rather than guessing', () {
    check(HttpDate.tryParse('not a date')).isNull();
    check(HttpDate.tryParse('Sun, 06 Xyz 1994 08:49:37 GMT')).isNull();
  });

  test('reads as the device clock until a response arrives', () {
    final clock = ServerClock();
    check(clock.offset).equals(Duration.zero);
    check(clock.now().difference(DateTime.now().toUtc()).inSeconds).equals(0);
  });

  test('tracks a server running ahead of the device', () {
    final clock = ServerClock();
    final ahead = DateTime.now().toUtc().add(const Duration(minutes: 5));

    _deliver(clock.interceptor, _responseDated(_rfc1123(ahead)));

    // The header carries no sub-second component, so the recorded offset falls
    // short by two things: the device clock's fractional second, which the
    // format drops, and however long delivery took before `_observe` read its
    // own `DateTime.now()`. That puts it in (298s, 300s].
    //
    // `inSeconds >= 299` accounted for the dropped fraction but not the
    // elapsed term, so it failed whenever the two summed past a second: rare
    // enough to survive months, and it duly took out a release run. Asserted
    // in milliseconds because `inSeconds` truncates, hiding the very
    // sub-second margin this is about.
    check(clock.offset.inMilliseconds).isGreaterThan(298000);
    check(clock.offset.inMilliseconds).isLessOrEqual(300000);
  });

  test('a countdown measures against server time, not device time', () {
    final clock = ServerClock();
    // Device clock is an hour slow. Naively subtracting device now from the
    // deadline would show an hour of turn time that does not exist.
    final serverNow = DateTime.now().toUtc().add(const Duration(hours: 1));
    _deliver(clock.interceptor, _responseDated(_rfc1123(serverNow)));

    final deadline = serverNow.add(const Duration(seconds: 30));
    final remaining = clock.remainingUntil(deadline.millisecondsSinceEpoch);

    check(remaining.inSeconds).isGreaterOrEqual(29);
    check(remaining.inSeconds).isLessOrEqual(30);
  });

  test('an elapsed deadline reads as zero, never negative', () {
    final clock = ServerClock();
    final past = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    check(
      clock.remainingUntil(past.millisecondsSinceEpoch),
    ).equals(Duration.zero);
  });

  test('ignores a response with no date header', () {
    final clock = ServerClock();
    _deliver(clock.interceptor, _responseDated(null));
    check(clock.offset).equals(Duration.zero);
  });
}

/// Formats [time] the way an HTTP `Date` header does.
String _rfc1123(DateTime time) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
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
  final t = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[t.weekday - 1]}, ${two(t.day)} ${months[t.month - 1]} '
      '${t.year} ${two(t.hour)}:${two(t.minute)}:${two(t.second)} GMT';
}
