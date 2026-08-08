import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Headless widget that ticks toward a [deadline], exposing the remaining
/// [Duration] to a [builder] callback every second.
///
/// The timer self-cancels once the deadline passes. Use this as the
/// computation layer beneath any styled countdown widget.
///
/// Set [isPaused] to freeze the displayed value without cancelling the
/// underlying timer; the frozen duration resumes from the correct wall-clock
/// value as soon as [isPaused] becomes false again.
///
/// [softMargin] shifts the *displayed* zero point earlier than [deadline] so
/// the player is nudged to submit before the true server deadline (absorbing
/// network latency). It is display-only; the server stays authoritative and
/// the expiry trigger uses the true deadline. Defaults to no margin.
class TurnTimerBuilder extends StatefulWidget {
  const TurnTimerBuilder({
    super.key,
    required this.deadline,
    required this.builder,
    this.softMargin = Duration.zero,
    this.isPaused = false,
  });

  final DateTime deadline;
  final Duration softMargin;
  final bool isPaused;

  /// Called every second with the remaining duration (clamped to zero).
  final Widget Function(BuildContext context, Duration remaining) builder;

  @override
  State<TurnTimerBuilder> createState() => _TurnTimerBuilderState();
}

class _TurnTimerBuilderState extends State<TurnTimerBuilder> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  /// The displayed deadline, pulled earlier by [TurnTimerBuilder.softMargin].
  DateTime get _effectiveDeadline =>
      widget.deadline.subtract(widget.softMargin);

  @override
  void initState() {
    super.initState();
    // Always compute the initial value so the widget is visible even when
    // created while paused (e.g. device is already offline on first render).
    _tickForced();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(TurnTimerBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline ||
        oldWidget.softMargin != widget.softMargin) {
      _timer?.cancel();
      _tickForced();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      return;
    }
    // Resync immediately when unpausing so the displayed value reflects the
    // wall-clock elapsed time rather than the frozen snapshot.
    if (oldWidget.isPaused && !widget.isPaused) _tickForced();
  }

  /// Updates [_remaining] regardless of [isPaused]. Used for the initial
  /// render and on deadline change so the widget is never invisibly blank.
  void _tickForced() {
    final r = _effectiveDeadline.difference(DateTime.now());
    if (!mounted) return;
    if (r.isNegative) {
      _timer?.cancel();
      setState(() => _remaining = Duration.zero);
    } else {
      setState(() => _remaining = r);
    }
  }

  void _tick() {
    if (widget.isPaused) return;
    final r = _effectiveDeadline.difference(DateTime.now());
    if (!mounted) return;
    if (r.isNegative) {
      _timer?.cancel();
      setState(() => _remaining = Duration.zero);
    } else {
      setState(() => _remaining = r);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _remaining);
}

/// Headless widget that computes a single player's remaining budget time,
/// exposing it to a [builder] callback every second.
///
/// The active player's bank drains live toward [deadline]; inactive players
/// receive their static [playerTimes] value. Use this as the computation layer
/// beneath any styled clock cell.
///
/// Only one bank drains at a time: budget mode permits a single pending seat,
/// so the turn deadline and the acting seat's remaining bank are the same
/// quantity. That is why the deadline alone is enough here, with no separate
/// turn-start to track and drift against.
///
/// Set [isPaused] to freeze the displayed value while offline.
class PlayerTimerBuilder extends StatefulWidget {
  const PlayerTimerBuilder({
    super.key,
    required this.playerTimes,
    required this.deadline,
    required this.pendingPlayers,
    required this.playerIndex,
    required this.builder,
    this.isPaused = false,
  });

  /// Remaining time in milliseconds per player, 0-indexed.
  final List<int> playerTimes;

  /// When the acting seat's bank runs out, on the device clock. Null in an
  /// untimed phase.
  final DateTime? deadline;

  /// Indices of currently active (draining) players.
  final List<int> pendingPlayers;

  /// The player whose time this widget tracks.
  final int playerIndex;

  final bool isPaused;

  /// Called every second with the computed remaining milliseconds and whether
  /// this player is currently active.
  final Widget Function(BuildContext context, int remainingMs, bool isActive)
  builder;

  @override
  State<PlayerTimerBuilder> createState() => _PlayerTimerBuilderState();
}

class _PlayerTimerBuilderState extends State<PlayerTimerBuilder> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Only rebuild when active and not paused; inactive players return a
      // static value so rebuilding every second is wasteful. Parent rebuilds
      // (new observation) still update inactive cells immediately via the
      // widget getters.
      if (mounted && _isActive && !widget.isPaused) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isActive => widget.pendingPlayers.contains(widget.playerIndex);

  int get _remainingMs {
    final base = widget.playerTimes[widget.playerIndex];
    final deadline = widget.deadline;
    if (!_isActive || deadline == null) return base;
    // Clamped to the frame's value as well as to zero: a clock skew correction
    // landing mid-turn must never make a bank appear to grow.
    final left = deadline.difference(DateTime.now()).inMilliseconds;
    return max(0, min(base, left));
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _remainingMs, _isActive);
}
