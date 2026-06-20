import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_engine/core/analytics/analytics_provider.dart';
import 'package:eigen_engine/core/errors/error_messages.dart';
import 'package:eigen_engine/core/game/game_creation_spec.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
import 'package:eigen_engine/features/game/presentation/widgets/timing_selector.dart';
import 'package:eigen_engine/features/game/providers/game_providers.dart';

/// Dialog for creating a new game.
///
/// Reads [GameModule.creationSpec] to render only the controls valid for the
/// current game type. Timing options come from [GameCreationSpec.timingConfigs]
/// — each map key is a [SegmentedButton] label; each value declares the
/// valid range and optional quick-pick presets.
class NewGameDialog extends ConsumerStatefulWidget {
  const NewGameDialog({super.key});

  @override
  ConsumerState<NewGameDialog> createState() => _NewGameDialogState();
}

class _NewGameDialogState extends ConsumerState<NewGameDialog> {
  GameAccess _access = GameAccess.public;
  late GameCreationSpec _spec;
  // Resolved timing from the shared TimingSelector; seeded with its default so
  // there is no null window before the first interaction.
  late ResolvedTiming _timing;

  // Plain fields — never displayed, only consumed at submit.
  Map<String, dynamic> _gameConfig = {};
  late int _minPlayers;
  late int _maxPlayers;
  Widget? _creationConfigWidget;
  bool _isLoading = false;

  // Rated toggle: on by default
  bool _rated = true;

  // Server-derived preview of whether the current config would be rated, shown
  // as a live badge. Null until the first preview returns.
  ({bool rated, String? pool})? _ratingPreview;

  @override
  void initState() {
    super.initState();
    final module = ref.read(currentGameModuleProvider);
    _spec = module.creationSpec;
    _timing = TimingSelector.initial(_spec.timingConfigs);
    _gameConfig = Map.of(_spec.defaultConfig);
    final (min, max) = module.playersForConfig(_gameConfig);
    _minPlayers = min;
    _maxPlayers = max;
    _creationConfigWidget = module.buildCreationConfig(
      onChanged: (config) {
        _gameConfig = config;
        final (newMin, newMax) = module.playersForConfig(config);
        _minPlayers = newMin;
        _maxPlayers = newMax;
        _refreshRatingPreview();
      },
    );
    _refreshRatingPreview();
  }

  /// Refreshes the Rated/Casual preview from the server (single source of truth,
  /// shared with create_game). Called when a rated-relevant input changes — the
  /// access mode, timing mode, game config, or the rated toggle. The specific
  /// slider seconds don't affect eligibility, so slider drags don't trigger it.
  void _refreshRatingPreview() {
    unawaited(() async {
      try {
        final preview = await ref
            .read(gameRepositoryProvider)
            .previewGameRating(
              access: _access,
              turnSeconds: _timing.turnSeconds,
              budgetSeconds: _timing.budgetSeconds,
              incrementSeconds: _timing.incrementSeconds,
              minPlayers: _minPlayers,
              maxPlayers: _maxPlayers,
              config: _gameConfig,
              ratedPreference: _rated,
            );
        if (mounted) setState(() => _ratingPreview = preview);
      } catch (_) {
        // Best-effort; keep the previous badge on a transient error.
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Guests cannot have friends and always play unrated, so the Friends access
    // segment is shown-but-disabled and the Rated toggle is hidden (the server
    // enforces both regardless).
    final isAnonymous = ref.watch(isAnonymousProvider);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New Game', style: textTheme.headlineSmall),
              const SizedBox(height: 24),

              // ── Access ────────────────────────────────────────────────
              Text('Access', style: textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<GameAccess>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(
                    value: GameAccess.public,
                    label: Text('Public'),
                  ),
                  const ButtonSegment(
                    value: GameAccess.private,
                    label: Text('Private'),
                  ),
                  // Shown but disabled for guests: they cannot have friends, so
                  // a friends-access game would be unjoinable (server enforces).
                  ButtonSegment(
                    value: GameAccess.friends,
                    label: const Text('Friends'),
                    enabled: !isAnonymous,
                  ),
                ],
                selected: {_access},
                onSelectionChanged: (s) => setState(() {
                  _access = s.first;
                  _refreshRatingPreview();
                }),
              ),
              const SizedBox(height: 16),

              // ── Timing ────────────────────────────────────────────────
              TimingSelector(
                configs: _spec.timingConfigs,
                enabled: !_isLoading,
                onChanged: (timing) => setState(() {
                  // Refresh the rated preview only when the mode changes; the
                  // specific slider seconds don't affect eligibility, so slider
                  // drags must not spam the server.
                  final modeChanged = timing.mode != _timing.mode;
                  _timing = timing;
                  if (modeChanged) _refreshRatingPreview();
                }),
              ),

              // ── Game-specific config ──────────────────────────────────
              if (_creationConfigWidget != null) ...[
                const SizedBox(height: 16),
                _creationConfigWidget!,
              ],

              // ── Rated toggle ──────────────────────────────────────────
              // Hidden for guests (they play unrated; the server enforces it
              // regardless). Otherwise always shown; the server silently
              // overrides to unrated if the game type doesn't support rating
              // for this configuration.
              if (!isAnonymous) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rated'),
                  value: _rated,
                  onChanged: (v) => setState(() {
                    _rated = v;
                    _refreshRatingPreview();
                  }),
                ),
              ],

              // Live Rated/Casual badge from the server (the authority on
              // eligibility — guests, ineligible config, etc.).
              if (_ratingPreview case final preview?) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      preview.rated
                          ? Icons.emoji_events_outlined
                          : Icons.sports_esports_outlined,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      preview.rated
                          ? 'Rated${preview.pool != null ? ' · ${preview.pool}' : ''}'
                          : 'Casual',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              // ── Actions ───────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isLoading ? null : _createGame,
                    child: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createGame() async {
    setState(() => _isLoading = true);
    try {
      final gameId = await ref
          .read(gameRepositoryProvider)
          .createGame(
            access: _access,
            turnSeconds: _timing.turnSeconds,
            budgetSeconds: _timing.budgetSeconds,
            incrementSeconds: _timing.incrementSeconds,
            minPlayers: _minPlayers,
            maxPlayers: _maxPlayers,
            config: _gameConfig,
            ratedPreference: _rated,
            schemaVersion: ref.read(currentGameModuleProvider).schemaVersion,
          );
      ref
          .read(analyticsServiceProvider)
          .gameCreated(
            gameId: gameId,
            access: _access.name,
            timingMode: _timing.mode,
            rated: _rated,
          );
      if (!mounted) return;
      Navigator.pop(context);
      context.pushNamed('game', pathParameters: {'gameId': gameId});
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanize(e))));
    }
  }
}
