import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:eigen_flutter/core/analytics/analytics_provider.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:eigen_flutter/core/connectivity/connectivity_provider.dart';
import 'package:eigen_flutter/shared/widgets/status_banner.dart';
import 'package:eigen_flutter/core/review/review_notifier.dart';
import 'package:eigen_flutter/core/utils/deep_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_flutter/core/errors/engine_exception.dart';
import 'package:eigen_flutter/core/errors/error_messages.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_flutter/core/game/players_context.dart';
import 'package:eigen_flutter/core/game/my_seat.dart';
import 'package:eigen_flutter/core/game/timing_constants.dart';
import 'package:eigen_flutter/core/game/timing_context.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:eigen_api/eigen_api.dart';


import 'package:eigen_flutter/features/game/presentation/widgets/budget_clock.dart';
import 'package:eigen_flutter/features/game/presentation/widgets/turn_countdown.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';
import 'package:eigen_flutter/features/game/providers/game_frame_provider.dart';

import 'package:eigen_flutter/features/social/presentation/widgets/player_profile_sheet.dart';
import 'package:eigen_flutter/shared/widgets/player_avatar.dart';
import 'package:eigen_flutter/shared/widgets/player_tags.dart';
import 'package:eigen_flutter/core/api/game_socket.dart';

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
  bool _errorSnackBarShown = false;
  late final AppLifecycleListener _lifecycleListener;
  late final ProviderSubscription<AsyncValue<Roster>> _gameStatusSub;
  late final ProviderSubscription<AsyncValue<List<Outcome>>> _outcomesSub;
  late final ProviderSubscription<bool> _offlineSub;
  late final ProviderSubscription<AsyncValue<GameSocketEvent>> _eventsSub;

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
      gameRosterProvider(gameId: widget.gameId),
      _onGameStatusChange,
    );
    _outcomesSub = ref.listenManual(
      gameOutcomesProvider(gameId: widget.gameId),
      _onOutcomes,
    );
    _offlineSub = ref.listenManual(isOfflineProvider, _onConnectivityChange);
    _eventsSub = ref.listenManual(
      gameEventsProvider(gameId: widget.gameId),
      _onGameEvent,
    );
  }

  void _onGameStatusChange(AsyncValue<Roster>? prev, AsyncValue<Roster> next) {
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

  void _onOutcomes(
    AsyncValue<List<Outcome>>? prev,
    AsyncValue<List<Outcome>> next,
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

  void _maybeTriggerWinHaptic(List<Outcome> outcomes) {
    final mySeat = ref
        .read(gamePlayersProvider(gameId: widget.gameId))
        .value
        ?.mySeat;
    if (mySeat is! Seated) return;
    final didWin = outcomes.any(
      (o) => o.playerIndex == mySeat.index && o.result == OutcomeResultEnum.win,
    );
    if (didWin) unawaited(HapticFeedback.heavyImpact());
  }

  void _onGameEvent(
    AsyncValue<GameSocketEvent>? prev,
    AsyncValue<GameSocketEvent> next,
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
        if (value is GameSocketFrame &&
            _pendingAction == _PendingAction.submittingAction) {
          setState(() => _pendingAction = null);
        }
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
            .read(gameRosterProvider(gameId: widget.gameId))
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
                      gameEventsProvider(gameId: widget.gameId),
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
  }

  /// Re-subscribes both Realtime streams immediately, bypassing Riverpod's
  /// retry backoff.
  void _invalidateStreams() {
    ref.invalidate(gameRosterProvider(gameId: widget.gameId));
    ref.invalidate(gameEventsProvider(gameId: widget.gameId));
  }

  /// Full refresh of every per-game provider this screen depends on.
  void _invalidateAllGameProviders() {
    _invalidateStreams();
    ref.invalidate(gamePlayersProvider(gameId: widget.gameId));
    ref.invalidate(gameOutcomesProvider(gameId: widget.gameId));
  }

  void _maybeRequestReview(List<Outcome> outcomes) {
    final mySeat = ref
        .read(gamePlayersProvider(gameId: widget.gameId))
        .value
        ?.mySeat;
    if (mySeat is! Seated) return;

    final myOutcome = outcomes
        .where((o) => o.playerIndex == mySeat.index)
        .firstOrNull;
    if (myOutcome?.result != OutcomeResultEnum.win) return;

    unawaited(ref.read(reviewProvider.notifier).onWin());
  }

  @override
  void dispose() {
    _gameStatusSub.close();
    _outcomesSub.close();
    _offlineSub.close();
    _eventsSub.close();
    _lifecycleListener.dispose();
    super.dispose();
  }

  /// Schedules (or cancels) a timer that fires [kExpiryTriggerDelay] *after*
  /// the [deadline], then calls `GameRepository.triggerTurnExpiry` so the server
  /// can process
  /// the timeout before the pg_cron job runs. Replaces any previously scheduled
  /// timer.
  ///
  /// The delay sits past the server's grace window
  /// ([kServerDeadlineGrace]) on purpose: nudging at exactly the deadline would
  /// hit the server while it is still abstaining, the nudge would no-op, and the
  /// timeout would slip to the next (every-minute) pg_cron sweep.


  @override
  Widget build(BuildContext context) {
    final gameAsync = ref.watch(gameSummaryProvider(gameId: widget.gameId));
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

  /// The caller's own seat, or null when they are only watching.
  ///
  /// Every state-changing command carries it: the server verifies the named
  /// seat against its roster rather than resolving one for the caller, so a
  /// seat nobody holds is a clean rejection instead of a guess.
  int? _mySeat() {
    final seat = ref
        .read(gamePlayersProvider(gameId: widget.gameId))
        .value
        ?.mySeat;
    return seat is Seated ? seat.index : null;
  }

  /// Submits an action and reports the outcome to the game's content widget
  /// (via [GameContentContext.onAction]). Error display stays here — the game
  /// only uses the [ActionSubmitResult] to manage optimistic rendering.
  ///
  /// An [EngineException] is a definitive server verdict → [rejected]; any
  /// other failure is transport-shaped, so the server may still have
  /// committed → [unconfirmed].
  Future<ActionSubmitResult> _submitAction(
    Map<String, dynamic> actionJson,
    int gameVersion,
  ) async {
    if (_pendingAction == _PendingAction.submittingAction) {
      return ActionSubmitResult.rejected;
    }
    unawaited(HapticFeedback.lightImpact());
    setState(() => _pendingAction = _PendingAction.submittingAction);

    try {
      final seat = _mySeat();
      if (seat == null) return ActionSubmitResult.rejected;
      await ref
          .read(gameRepositoryProvider)
          .submitAction(
            gameId: widget.gameId,
            seat: seat,
            data: actionJson,
            expectedVersion: gameVersion,
          );
      // Keep _pendingAction = submittingAction on success.
      // The observation listener resets it when the confirming update arrives.
      return ActionSubmitResult.committed;
    } on EngineException catch (e) {
      _onSubmitFailed(e);
      return ActionSubmitResult.rejected;
    } catch (e) {
      _onSubmitFailed(e);
      return ActionSubmitResult.unconfirmed;
    }
  }

  void _onSubmitFailed(Object e) {
    if (!mounted) return;
    setState(() => _pendingAction = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(humanize(e))));
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
      final seat = _mySeat();
      if (seat == null) return;
      await ref
          .read(gameRepositoryProvider)
          .forfeitGame(gameId: widget.gameId, seat: seat);
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

  final GameSummary game;

  /// The in-flight user operation, if any. Leaf widgets receive the specific
  /// booleans they need, derived here.
  final _PendingAction? pendingAction;
  final VoidCallback onStartGame;
  final VoidCallback onCancelGame;
  final VoidCallback onLeaveGame;
  final Future<ActionSubmitResult> Function(Map<String, dynamic>, int) onAction;
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

      case GameStatus.aborted:
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
