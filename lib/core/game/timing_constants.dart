import 'dart:math' as math;

/// Client-side timing constants for the turn-deadline display.
///
/// The server is the sole authority on deadlines: a game's Durable Object holds
/// an alarm at the current turn's deadline and expires the turn itself, so the
/// client never nudges it and never needs to model the server's grace window.
/// These constants only shape what the client *displays*; they can never cause
/// a wrong rejection or a wrong timeout.

/// Target headroom subtracted from a player's *displayed* countdown so an
/// on-time submit reaches the server before the true deadline.
const Duration kSoftDeadlineMargin = Duration(seconds: 1);

/// Upper bound on the soft margin as a fraction of the current turn window, so
/// short per-action / hook-override windows (e.g. a 3 s Nope) are not swallowed.
const double kSoftDeadlineMaxFraction = 0.25;

/// The soft-deadline margin for a turn [window], capped at
/// [kSoftDeadlineMaxFraction] of the window.
///
/// Returns [Duration.zero] for a non-positive window (untimed / already
/// expired), which makes callers fall back to truthful, unmargined display.
Duration softDeadlineMarginFor(Duration window) {
  if (window <= Duration.zero) return Duration.zero;
  final capMicros = (window.inMicroseconds * kSoftDeadlineMaxFraction).round();
  final marginMicros = math.min(kSoftDeadlineMargin.inMicroseconds, capMicros);
  return Duration(microseconds: marginMicros);
}
