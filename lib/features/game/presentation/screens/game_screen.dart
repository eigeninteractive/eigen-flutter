import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:eigen_engine/core/analytics/analytics_provider.dart';
import 'package:eigen_engine/core/config/app_config.dart';
import 'package:eigen_engine/core/connectivity/connectivity_provider.dart';
import 'package:eigen_engine/shared/widgets/status_banner.dart';
import 'package:eigen_engine/core/review/review_notifier.dart';
import 'package:eigen_engine/core/utils/deep_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_engine/core/errors/error_messages.dart';
import 'package:eigen_engine/core/game/game_module.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/core/game/players_context.dart';
import 'package:eigen_engine/core/game/game_status.dart';
import 'package:eigen_engine/core/game/timing_constants.dart';
import 'package:eigen_engine/core/game/timing_context.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/game/data/models/bot_info.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
import 'package:eigen_engine/features/game/data/models/observation.dart';
import 'package:eigen_engine/features/game/presentation/widgets/budget_clock.dart';
import 'package:eigen_engine/features/game/presentation/widgets/turn_countdown.dart';
import 'package:eigen_engine/features/game/providers/game_providers.dart';
import 'package:eigen_engine/features/game/providers/game_frame_provider.dart';
import 'package:eigen_engine/features/game/providers/local_bot_driver.dart';
import 'package:eigen_engine/features/social/presentation/widgets/player_profile_sheet.dart';
import 'package:eigen_engine/shared/widgets/player_avatar.dart';

part 'game_screen_pre_game.dart';
part 'game_screen_active.dart';
part 'game_screen_states.dart';

/// Screen for playing a game.
///
/// Dispatches on [Game.status] before touching the observation stream:
/// - waiting/ready → [_PreGameContent] (no observation needed)
/// - aborted → [_AbortedContent] (no observation needed)
/// - active/finished → [_ActiveGameContent] (session required)
///
/// A single [RefreshIndicator] wraps all branches. Every branch returns a
/// [CustomScrollView] with [AlwaysScrollableScrollPhysics] so pull-to-refresh
/// is detectable even when content is shorter than the viewport.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.gameId});

  final String gameId;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

enum _PendingAction {
  starting,
  submittingAction,
  cancelling,
  forfeiting,
  leaving,
}

class _GameScreenState extends ConsumerState<GameScreen> {
  _PendingAction? _pendingAction;
  Timer? _deadlineTimer;
  bool _pendingExpiry = false;
  bool _errorSnackBarShown = false;
  late final AppLifecycleListener _lifecycleListener;
  late final ProviderSubscription<AsyncValue<Game>> _gameStatusSub;
  late final ProviderSubscription<AsyncValue<List<GameOutcome>>> _outcomesSub;
  late final ProviderSubscription<bool> _offlineSub;
  late final ProviderSubscription<AsyncValue<Observation>> _observationSub;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: _invalidateAllGameProviders,
    );
    // Analytics listeners registered once here so they are independent of the
    // build cycle and don't mix side-effects into the build method.
    // Registered before the build-cycle listeners so they read player count
    // before gamePlayersProvider is invalidated on status change.
    _gameStatusSub = ref.listenManual(
      gameStreamProvider(gameId: widget.gameId),
      _onGameStatusChange,
    );
    _outcomesSub = ref.listenManual(
      gameOutcomesProvider(gameId: widget.gameId),
      _onGameOutcomes,
    );
    _offlineSub = ref.listenManual(isOfflineProvider, _onConnectivityChange);
    _observationSub = ref.listenManual(
      gameObservationProvider(gameId: widget.gameId),
      _onObservation,
    );
  }

  void _onGameStatusChange(AsyncValue<Game>? prev, AsyncValue<Game> next) {
    final prevStatus = prev?.value?.status;
    final status = next.value?.status;
    if (prevStatus == status) return;

    // Fire game_started only on a witnessed pre-game → active transition.
    // prevStatus is null on the first load after mounting, so merely opening
    // an already-active game does not re-count the start.
    if (status == GameStatus.active &&
        (prevStatus == GameStatus.waiting || prevStatus == GameStatus.ready)) {
      // Read player count before invalidating below so the cached value is
      // still available for the analytics call.
      final count =
          ref
              .read(gamePlayersProvider(gameId: widget.gameId))
              .value
              ?.players
              .length ??
          0;
      unawaited(
        ref
            .read(analyticsServiceProvider)
            .gameStarted(gameId: widget.gameId, playerCount: count),
      );
    }

    // Refresh player list on any status transition so the waiting room
    // immediately reflects new joiners without requiring a manual pull.
    ref.invalidate(gamePlayersProvider(gameId: widget.gameId));

    if (status == GameStatus.finished) {
      ref.invalidate(gameOutcomesProvider(gameId: widget.gameId));
    }
  }

  void _onGameOutcomes(
    AsyncValue<List<GameOutcome>>? prev,
    AsyncValue<List<GameOutcome>> next,
  ) {
    // Side effects fire only on a witnessed empty → non-empty transition.
    // prev?.value is null on first load (re-opening a finished game must not
    // re-fire) and non-empty during reloads (AsyncLoading carries previous
    // data in Riverpod 3.x, guarding against app-resume re-firing).
    if (prev?.value?.isEmpty != true) return;
    if (next.value?.isEmpty ?? true) return;
    unawaited(
      ref.read(analyticsServiceProvider).gameFinished(gameId: widget.gameId),
    );
    _maybeRequestReview(next.value!);
    _maybeTriggerWinHaptic(next.value!);
  }

  void _maybeTriggerWinHaptic(List<GameOutcome> outcomes) {
    final myPlayerIndex = ref
        .read(gamePlayersProvider(gameId: widget.gameId))
        .value
        ?.myPlayerIndex;
    if (myPlayerIndex == null || myPlayerIndex < 0) return;
    final didWin = outcomes.any(
      (o) => o.playerIndex == myPlayerIndex && o.result == OutcomeResult.win,
    );
    if (didWin) unawaited(HapticFeedback.heavyImpact());
  }

  void _onObservation(
    AsyncValue<Observation>? prev,
    AsyncValue<Observation> next,
  ) {
    if (!mounted) return;
    // Use AsyncData pattern — next.value returns previous data even during
    // AsyncLoading/AsyncError in Riverpod 3.x, which would cause premature
    // action-pending reset during pull-to-refresh or app resume.
    switch (next) {
      case AsyncData(:final value):
        if (_errorSnackBarShown) {
          _errorSnackBarShown = false;
          ScaffoldMessenger.of(context).clearSnackBars();
        }
        if (_pendingAction == _PendingAction.submittingAction) {
          setState(() => _pendingAction = null);
        }
        _scheduleDeadlineTimer(value.turnDeadline);
      case AsyncError():
        if (_pendingAction == _PendingAction.submittingAction) {
          setState(() => _pendingAction = null);
        }
        // One snackbar per error episode, terminal or not — Riverpod's retry
        // cycle would otherwise re-show it on every failed attempt. The flag
        // resets on the next successful observation.
        if (_errorSnackBarShown) return;
        _errorSnackBarShown = true;
        final status = ref
            .read(gameStreamProvider(gameId: widget.gameId))
            .value
            ?.status;
        final isTerminal =
            status == GameStatus.finished || status == GameStatus.aborted;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isTerminal
                  ? 'This game has ended.'
                  : 'Connection lost. Retrying…',
            ),
            action: isTerminal
                ? SnackBarAction(
                    label: 'Back to Home',
                    onPressed: () => context.go('/home'),
                  )
                : SnackBarAction(
                    label: 'Retry',
                    onPressed: () => ref.invalidate(
                      gameObservationProvider(gameId: widget.gameId),
                    ),
                  ),
            duration: const Duration(seconds: 10),
          ),
        );
      default:
        break;
    }
  }

  void _onConnectivityChange(bool? wasOffline, bool isOffline) {
    if (wasOffline != true || isOffline) return;
    // Network restored — re-subscribe immediately for the fast
    // offline→online transition.
    _invalidateStreams();
    if (_pendingExpiry) {
      _pendingExpiry = false;
      unawaited(_triggerExpiry());
    }
  }

  /// Re-subscribes both Realtime streams immediately, bypassing Riverpod's
  /// retry backoff.
  void _invalidateStreams() {
    ref.invalidate(gameStreamProvider(gameId: widget.gameId));
    ref.invalidate(gameObservationProvider(gameId: widget.gameId));
  }

  /// Full refresh of every per-game provider this screen depends on.
  void _invalidateAllGameProviders() {
    _invalidateStreams();
    ref.invalidate(gamePlayersProvider(gameId: widget.gameId));
    ref.invalidate(gameOutcomesProvider(gameId: widget.gameId));
  }

  void _maybeRequestReview(List<GameOutcome> outcomes) {
    final myPlayerIndex = ref
        .read(gamePlayersProvider(gameId: widget.gameId))
        .value
        ?.myPlayerIndex;
    if (myPlayerIndex == null || myPlayerIndex < 0) return;

    final myOutcome = outcomes
        .where((o) => o.playerIndex == myPlayerIndex)
        .firstOrNull;
    if (myOutcome?.result != OutcomeResult.win) return;

    unawaited(ref.read(reviewProvider.notifier).onWin());
  }

  @override
  void dispose() {
    _gameStatusSub.close();
    _outcomesSub.close();
    _offlineSub.close();
    _observationSub.close();
    _deadlineTimer?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  /// Schedules (or cancels) a timer that fires [kExpiryTriggerDelay] *after*
  /// the [deadline], then calls [trigger_turn_expiry] so the server can process
  /// the timeout before the pg_cron job runs. Replaces any previously scheduled
  /// timer.
  ///
  /// The delay sits past the server's grace window
  /// ([kServerDeadlineGrace]) on purpose: nudging at exactly the deadline would
  /// hit the server while it is still abstaining, the nudge would no-op, and the
  /// timeout would slip to the next (every-minute) pg_cron sweep.
  void _scheduleDeadlineTimer(DateTime? deadline) {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    if (deadline == null) return;
    final delay = deadline.add(kExpiryTriggerDelay).difference(DateTime.now());
    _deadlineTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      _triggerExpiry,
    );
  }

  Future<void> _triggerExpiry() async {
    if (ref.read(isOfflineProvider)) {
      // Queue the nudge for when connectivity returns; pg_cron is the backstop.
      _pendingExpiry = true;
      return;
    }
    try {
      await ref.read(gameRepositoryProvider).triggerTurnExpiry(widget.gameId);
    } catch (_) {
      // Server re-validates under lock; errors here are expected when the
      // game has already ended or the deadline was extended by a concurrent action.
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameAsync = ref.watch(gameStreamProvider(gameId: widget.gameId));
    // Keep the local-bot driver alive while this screen is shown. Its state is
    // void (it never rebuilds); watching it is what lets it react to game,
    // engine, players and observation changes and drive pending local-bot seats.
    ref.watch(localBotDriverProvider(gameId: widget.gameId));

    return Scaffold(
      body: Column(
        children: [
          _ReconnectingBannerSlot(gameId: widget.gameId),
          Expanded(
            child: SafeArea(
              child: switch (gameAsync) {
                // value is non-null for AsyncData and for AsyncError with
                // stale data — keep showing the game while the banner
                // communicates the reconnecting state.
                _ when gameAsync.value != null => RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: _GameBody(
                    game: gameAsync.value!,
                    pendingAction: _pendingAction,
                    onStartGame: _startGame,
                    onCancelGame: _cancelGame,
                    onLeaveGame: _leaveGame,
                    onAction: _submitAction,
                    onForfeit: _forfeitGame,
                  ),
                ),
                AsyncError(:final error) => _ErrorState(
                  error: humanize(error),
                  onRetry: _retryConnection,
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ),
        ],
      ),
    );
  }

  void _retryConnection() => _invalidateStreams();

  Future<void> _onRefresh() async {
    _invalidateAllGameProviders();
    await ref.read(gamePlayersProvider(gameId: widget.gameId).future);
  }

  Future<void> _submitAction(
    Map<String, dynamic> actionJson,
    int gameVersion,
  ) async {
    if (_pendingAction == _PendingAction.submittingAction) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() => _pendingAction = _PendingAction.submittingAction);

    try {
      await ref
          .read(gameRepositoryProvider)
          .submitAction(
            gameId: widget.gameId,
            actionData: actionJson,
            expectedVersion: gameVersion,
          );
      // Keep _pendingAction = submittingAction on success.
      // The observation listener resets it when the confirming update arrives.
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingAction = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanize(e))));
    }
  }

  Future<void> _cancelGame() async {
    setState(() => _pendingAction = _PendingAction.cancelling);
    try {
      await ref.read(gameRepositoryProvider).cancelGame(widget.gameId);
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingAction = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanize(e))));
    }
  }

  Future<void> _leaveGame() async {
    setState(() => _pendingAction = _PendingAction.leaving);
    try {
      await ref.read(gameRepositoryProvider).leaveGame(widget.gameId);
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingAction = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanize(e))));
    }
  }

  Future<void> _startGame() async {
    setState(() => _pendingAction = _PendingAction.starting);
    try {
      await ref.read(gameRepositoryProvider).startGame(widget.gameId);
      if (mounted) setState(() => _pendingAction = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingAction = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanize(e))));
    }
  }

  Future<void> _forfeitGame() async {
    setState(() => _pendingAction = _PendingAction.forfeiting);
    try {
      await ref.read(gameRepositoryProvider).forfeitGame(widget.gameId);
      if (mounted) {
        setState(() => _pendingAction = null);
        unawaited(ref.read(analyticsServiceProvider).forfeit());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingAction = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanize(e))));
    }
  }
}

/// Routes game status to the correct scroll branch.
///
/// All branches return a [CustomScrollView] with [AlwaysScrollableScrollPhysics]
/// so the parent [RefreshIndicator] can detect a pull in every game state.
///
/// A pure routing widget — provider subscriptions are owned by the leaf
/// widgets ([_PreGameContent], [_ActiveGameContent]) so observation updates
/// only rebuild the subtree that needs them.
class _GameBody extends StatelessWidget {
  const _GameBody({
    required this.game,
    required this.pendingAction,
    required this.onStartGame,
    required this.onCancelGame,
    required this.onLeaveGame,
    required this.onAction,
    required this.onForfeit,
  });

  final Game game;

  /// The in-flight user operation, if any. Leaf widgets receive the specific
  /// booleans they need, derived here.
  final _PendingAction? pendingAction;
  final VoidCallback onStartGame;
  final VoidCallback onCancelGame;
  final VoidCallback onLeaveGame;
  final Future<void> Function(Map<String, dynamic>, int) onAction;
  final Future<void> Function() onForfeit;

  @override
  Widget build(BuildContext context) {
    switch (game.status) {
      case GameStatus.waiting:
      case GameStatus.ready:
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _PreGameContent(
                game: game,
                isStartingGame: pendingAction == _PendingAction.starting,
                isCancelling: pendingAction == _PendingAction.cancelling,
                isLeaving: pendingAction == _PendingAction.leaving,
                onStartGame: onStartGame,
                onCancelGame: onCancelGame,
                onLeaveGame: onLeaveGame,
              ),
            ),
          ],
        );

      // An unrecognised status (newer server value) is treated as aborted —
      // the client can't safely render a state it doesn't understand.
      case GameStatus.aborted:
      case GameStatus.unknown:
        return const CustomScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(hasScrollBody: false, child: _AbortedContent()),
          ],
        );

      case GameStatus.active:
      case GameStatus.finished:
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _ActiveGameContent(
                game: game,
                isSubmittingAction:
                    pendingAction == _PendingAction.submittingAction,
                isForfeiting: pendingAction == _PendingAction.forfeiting,
                onAction: onAction,
                onForfeit: onForfeit,
              ),
            ),
          ],
        );
    }
  }
}
