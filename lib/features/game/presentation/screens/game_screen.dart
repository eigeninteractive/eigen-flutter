import 'dart:async';

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
import 'package:eigen_engine/core/game/timing_context.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
import 'package:eigen_engine/features/game/data/models/observation.dart';
import 'package:eigen_engine/features/game/presentation/widgets/budget_clock.dart';
import 'package:eigen_engine/features/game/presentation/widgets/turn_countdown.dart';
import 'package:eigen_engine/features/game/providers/game_providers.dart';
import 'package:eigen_engine/features/game/providers/game_frame_provider.dart';
import 'package:eigen_engine/features/social/presentation/widgets/player_profile_sheet.dart';
import 'package:eigen_engine/shared/widgets/player_avatar.dart';

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

  /// Schedules (or cancels) a timer that fires when [deadline] is reached,
  /// then calls [trigger_turn_expiry] so the server can process the timeout
  /// before the pg_cron job runs. Replaces any previously scheduled timer.
  void _scheduleDeadlineTimer(DateTime? deadline) {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    if (deadline == null) return;
    final delay = deadline.difference(DateTime.now());
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

/// Waiting room shown for [GameStatus.waiting] and [GameStatus.ready].
///
/// Does not require an observation — game_states and observations are only
/// created at [GameStatus.active] transition.
class _PreGameContent extends ConsumerWidget {
  const _PreGameContent({
    required this.game,
    required this.isStartingGame,
    required this.isCancelling,
    required this.isLeaving,
    required this.onStartGame,
    required this.onCancelGame,
    required this.onLeaveGame,
  });

  final Game game;
  final bool isStartingGame;
  final bool isCancelling;
  final bool isLeaving;
  final VoidCallback onStartGame;
  final VoidCallback onCancelGame;
  final VoidCallback onLeaveGame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamePlayersAsync = ref.watch(gamePlayersProvider(gameId: game.id));
    final currentUser = ref.watch(currentUserProvider);
    final appHost = ref.watch(appConfigProvider).engine.appHost;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCreator = game.createdBy == currentUser?.id;
    final isReady = game.status == GameStatus.ready;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReady ? Icons.people : Icons.hourglass_empty,
              size: 52,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            isReady ? 'All players ready!' : 'Waiting for players...',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Game #${game.id.substring(0, 8)}',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (game.shortCode != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.key, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    game.shortCode!,
                    style: textTheme.titleLarge?.copyWith(
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (gameInviteLink(game.shortCode!, appHost: appHost)
                case final link?) ...[
              const SizedBox(height: 16),
              // QR modules must be dark-on-light for scanner compatibility,
              // so the inner background is always white regardless of theme.
              // The card wrapper integrates it visually with the surface.
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: link.toString(),
                    version: QrVersions.auto,
                    size: 160,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: game.shortCode!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy code'),
                ),
                if (gameInviteLink(game.shortCode!, appHost: appHost)
                    case final link?) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: link.toString()),
                    ),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share link'),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 36),
          if (gamePlayersAsync.value case final gamePlayers?)
            _ParticipantList(
              playersContext: gamePlayers,
              currentUserId: currentUser?.id,
            ),
          const SizedBox(height: 36),
          if (isReady && isCreator)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: isStartingGame ? null : onStartGame,
                  icon: isStartingGame
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const Text('Start Game'),
                ),
                const SizedBox(width: 12),
                _CancelButton(
                  isCancelling: isCancelling,
                  onCancel: onCancelGame,
                  label: 'Cancel',
                ),
              ],
            ),
          if (!isReady && isCreator)
            _CancelButton(
              isCancelling: isCancelling,
              onCancel: onCancelGame,
              label: 'Cancel Game',
            ),
          if (!isCreator)
            OutlinedButton.icon(
              onPressed: isLeaving ? null : onLeaveGame,
              icon: isLeaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.exit_to_app),
              label: const Text('Leave Game'),
            ),
        ],
      ),
    );
  }
}

/// Participant slots shown in the pre-game waiting room.
class _ParticipantList extends StatelessWidget {
  const _ParticipantList({
    required this.playersContext,
    required this.currentUserId,
  });

  final PlayersContext playersContext;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final players = playersContext.players.values.toList();

    return Column(
      children: players.map((gp) {
        final isMe = gp.playerIndex == playersContext.myPlayerIndex;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAvatar(
                playerInfo: gp.info,
                radius: 20,
                onTap: () => PlayerProfileSheet.show(
                  context,
                  playerId: gp.info.id,
                  type: gp.type,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isMe ? 'You' : '@${gp.info.username}',
                style: textTheme.bodyMedium,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Shown for aborted games — cancelled by the host before starting, or
/// closed by the idle-cleanup job (which also aborts long-abandoned
/// untimed active games), so the copy stays neutral about timing.
class _AbortedContent extends StatelessWidget {
  const _AbortedContent();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cancel_outlined,
              size: 72,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'Game Cancelled',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This game was cancelled or closed due to inactivity.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a game's schema version exceeds what this build supports — it was
/// created by a newer app version, so the user must update to view it.
class _UnsupportedSchemaContent extends StatelessWidget {
  const _UnsupportedSchemaContent();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.system_update,
              size: 72,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'Update Required',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This game was created with a newer version of the app. '
              'Please update to view it.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The active/finished game board and status.
///
/// Uses [currentGameModuleProvider] to render game-specific content, keeping
/// [game_screen.dart] decoupled from any concrete game implementation.
///
/// Owns [gameFrameProvider] and [gamePlayersProvider] subscriptions so
/// observation updates rebuild only this widget, not the parent [_GameBody].
class _ActiveGameContent extends ConsumerWidget {
  const _ActiveGameContent({
    required this.game,
    required this.isSubmittingAction,
    required this.isForfeiting,
    required this.onAction,
    required this.onForfeit,
  });

  final Game game;
  final bool isSubmittingAction;
  final bool isForfeiting;
  final Future<void> Function(Map<String, dynamic>, int) onAction;
  final Future<void> Function() onForfeit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // gameEngineProvider (engine/data layer) is the single authority on whether
    // this build can load the game; here we only render its verdict. A game from
    // a newer build surfaces as UnsupportedGameSchemaException.
    final engineAsync = ref.watch(gameEngineProvider(gameId: game.id));
    if (engineAsync.error is UnsupportedGameSchemaException) {
      return const _UnsupportedSchemaContent();
    }

    final engine = engineAsync.value;
    final frame = ref.watch(gameFrameProvider(gameId: game.id));
    final gamePlayersAsync = ref.watch(gamePlayersProvider(gameId: game.id));

    if (engine == null ||
        frame == null ||
        frame.observation == null ||
        !gamePlayersAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final gamePlayers = gamePlayersAsync.value!;
    final module = ref.watch(currentGameModuleProvider);
    final myPlayerIndex = gamePlayers.myPlayerIndex;

    // Outcomes are fetched once when the game finishes (invalidated by the
    // gameStreamProvider listener in _GameScreenState). Empty list for active
    // games — no outcome rows exist yet.
    final outcomes =
        ref
            .watch(gameOutcomesProvider(gameId: game.id))
            .whenOrNull(data: (o) => o) ??
        const <GameOutcome>[];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (game.status == GameStatus.active)
            _TimingHeader(
              game: game,
              timing: frame.timing,
              pendingPlayers: frame.pendingPlayers,
              myPlayerIndex: myPlayerIndex,
            ),
          Expanded(
            child: module.buildContent(
              GameContentContext(
                engine: engine,
                frame: frame,
                gameStatus: game.status,
                outcomes: outcomes,
                actionPending: isSubmittingAction,
                onAction: (actionJson) => onAction(actionJson, frame.version),
                onInvalidAction: () =>
                    unawaited(HapticFeedback.selectionClick()),
                playersContext: gamePlayers,
              ),
            ),
          ),
          if (game.status == GameStatus.active)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ForfeitButton(
                isForfeiting: isForfeiting,
                onForfeit: onForfeit,
              ),
            ),
          if (game.status == GameStatus.finished)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: OutlinedButton.icon(
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Home'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Selects the right timing widget based on the game's timing mode.
///
/// Budget mode → [BudgetClock] (all players' banks, live drain on active).
/// Per-action or hook-override deadline → [TurnCountdown] (single shared timer).
/// Untimed → empty.
class _TimingHeader extends StatelessWidget {
  const _TimingHeader({
    required this.game,
    required this.timing,
    required this.pendingPlayers,
    required this.myPlayerIndex,
  });

  final Game game;
  final TimingContext timing;
  final List<int> pendingPlayers;
  final int myPlayerIndex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (game.budgetSeconds != null) {
      if (timing.playerTimes case final playerTimes?) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BudgetClock(
            playerTimes: playerTimes,
            turnStartedAt: timing.turnStartedAt,
            pendingPlayers: pendingPlayers,
            myPlayerIndex: myPlayerIndex,
          ),
        );
      }
    }

    if (timing.turnDeadline case final deadline?) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            TurnCountdown(
              deadline: deadline,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Forfeit button that shows a confirmation dialog before calling [onForfeit].
class _ForfeitButton extends StatelessWidget {
  const _ForfeitButton({required this.isForfeiting, required this.onForfeit});

  final bool isForfeiting;
  final VoidCallback onForfeit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: colorScheme.error),
      onPressed: isForfeiting ? null : () => _confirm(context),
      icon: isForfeiting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.flag_outlined),
      label: const Text('Forfeit'),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Forfeit game?'),
        content: const Text(
          'Are you sure you want to forfeit this game? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Forfeit'),
          ),
        ],
      ),
    );
    if (confirmed == true) onForfeit();
  }
}

/// Outlined cancel button with loading spinner state.
class _CancelButton extends StatelessWidget {
  const _CancelButton({
    required this.isCancelling,
    required this.onCancel,
    required this.label,
  });

  final bool isCancelling;
  final VoidCallback onCancel;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: isCancelling ? null : onCancel,
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.error,
        side: BorderSide(color: colorScheme.error),
      ),
      icon: isCancelling
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cancel_outlined),
      label: Text(label),
    );
  }
}

/// Shows [_ReconnectingBanner] when disconnected during any in-progress game
/// state (waiting, ready, or active).
///
/// Disconnected means device-level offline, the observation stream is in
/// [AsyncError], or the game stream itself is in [AsyncError] — covering
/// transient Supabase blips where [isOfflineProvider] stays false. Uses
/// [AsyncValue.value] to read stale status during error states. Isolated as a
/// [ConsumerWidget] leaf so changes don't rebuild the entire game tree.
class _ReconnectingBannerSlot extends ConsumerWidget {
  const _ReconnectingBannerSlot({required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    final obsAsync = ref.watch(gameObservationProvider(gameId: gameId));
    final gameAsync = ref.watch(gameStreamProvider(gameId: gameId));
    final isDisconnected =
        isOffline || obsAsync is AsyncError || gameAsync is AsyncError;

    // Use .value to read stale status when stream is in AsyncError.
    final status = gameAsync.value?.status;
    final isInGame =
        status != null &&
        status != GameStatus.finished &&
        status != GameStatus.aborted;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: (isDisconnected && isInGame)
          ? const _ReconnectingBanner()
          : const SizedBox.shrink(),
    );
  }
}

/// Slim banner shown when connectivity drops during an active game.
class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return StatusBanner(
      leading: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
      label: 'Reconnecting…',
      backgroundColor: colorScheme.secondaryContainer,
      foregroundColor: colorScheme.onSecondaryContainer,
    );
  }
}

/// Generic error state with retry button.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: colorScheme.error),
          const SizedBox(height: 16),
          Text('Error: $error'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
