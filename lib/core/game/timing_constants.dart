import 'dart:math' as math;

/// Client-side timing constants for the deadline/grace system.
///
/// The server is the sole authority on deadlines (see `submit_action`,
/// `expire_turn`, and `private.deadline_grace_ms()` in the SQL migrations).
/// These constants only shape what the client *displays* and *when it nudges*
/// the server — they can never cause a wrong rejection or timeout on their own.

/// Grace window the server adds to every deadline comparison before it rejects
/// an action or fires a timeout.
///
/// Mirrors `private.deadline_grace_ms()` (750 ms) in the SQL migrations. The
/// two are hardcoded independently — keep them in sync if either changes.
const Duration kServerDeadlineGrace = Duration(milliseconds: 750);

/// Safety margin added on top of [kServerDeadlineGrace] when scheduling the
/// expiry nudge, absorbing client timer jitter and clock skew so the nudge
/// cannot fire while the device clock still places it inside the grace window.
const Duration kExpiryTriggerEpsilon = Duration(milliseconds: 250);

/// Delay past the true deadline before the client nudges the server to process
/// a timeout (`trigger_turn_expiry`).
///
/// Derived as [kServerDeadlineGrace] + [kExpiryTriggerEpsilon] so it always
/// sits beyond the server's abstain window — otherwise `expire_turn` no-ops and
/// the timeout slips to the next (coarse, every-minute) pg_cron sweep. Only
/// affects the AFK/timeout path; a player who acts is never delayed by it.
final Duration kExpiryTriggerDelay =
    kServerDeadlineGrace + kExpiryTriggerEpsilon;

/// Target headroom subtracted from a player's *displayed* countdown so an
/// on-time submit reaches the server before the true deadline.
///
/// Display/nudge only — never applied to the expiry trigger.
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
