import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_engine/core/analytics/analytics_provider.dart';
import 'package:eigen_engine/core/errors/error_messages.dart';
import 'package:eigen_engine/core/game/game_creation_spec.dart';
import 'package:eigen_engine/features/game/data/models/game.dart';
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
  late String _timingKey;

  // Per-action slider value (seconds).
  double _turnSeconds = kMinTurnSeconds.toDouble();
  // Budget slider values (seconds).
  double _budgetSeconds = kMinBudgetSeconds.toDouble();
  double _incrementSeconds = 0;

  // Plain fields — never displayed, only consumed at submit.
  Map<String, dynamic> _gameConfig = {};
  late int _minPlayers;
  late int _maxPlayers;
  Widget? _creationConfigWidget;
  bool _isLoading = false;

  // Rated toggle: on by default
  bool _rated = true;

  @override
  void initState() {
    super.initState();
    final module = ref.read(currentGameModuleProvider);
    _spec = module.creationSpec;
    _timingKey = _spec.timingConfigs.keys.first;
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
      },
    );
    _setTimingDefaults(_spec.timingConfigs[_timingKey]!);
  }

  /// Sets slider fields to sensible defaults for [config].
  /// Must be called either from [initState] (no setState) or inside setState.
  void _setTimingDefaults(TimingModeConfig config) {
    switch (config) {
      case UntimedConfig():
        break;
      case PerActionConfig(:final presets, :final minSeconds):
        _turnSeconds = (presets.isNotEmpty ? presets.first : minSeconds)
            .toDouble();
      case BudgetConfig(
        :final presets,
        :final minBudgetSeconds,
        :final minIncrementSeconds,
      ):
        _budgetSeconds = presets.isNotEmpty
            ? presets.first.budget.toDouble()
            : minBudgetSeconds.toDouble();
        _incrementSeconds = presets.isNotEmpty
            ? presets.first.increment.toDouble()
            : minIncrementSeconds.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final configs = _spec.timingConfigs;
    final selectedConfig = configs[_timingKey]!;

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
                segments: const [
                  ButtonSegment(
                    value: GameAccess.public,
                    label: Text('Public'),
                  ),
                  ButtonSegment(
                    value: GameAccess.private,
                    label: Text('Private'),
                  ),
                  ButtonSegment(
                    value: GameAccess.friends,
                    label: Text('Friends'),
                  ),
                ],
                selected: {_access},
                onSelectionChanged: (s) => setState(() => _access = s.first),
              ),
              const SizedBox(height: 16),

              // ── Timing ────────────────────────────────────────────────
              Text('Timing', style: textTheme.labelLarge),
              const SizedBox(height: 8),

              // Mode selector — only shown when there are multiple options.
              if (configs.length > 1) ...[
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: configs.keys
                      .map((k) => ButtonSegment(value: k, label: Text(k)))
                      .toList(),
                  selected: {_timingKey},
                  onSelectionChanged: (s) => setState(() {
                    _timingKey = s.first;
                    _setTimingDefaults(configs[_timingKey]!);
                  }),
                ),
                const SizedBox(height: 12),
              ],

              // Mode-specific controls.
              switch (selectedConfig) {
                UntimedConfig() => const SizedBox.shrink(),
                final PerActionConfig c => _PerActionPanel(
                  config: c,
                  value: _turnSeconds,
                  onChanged: (v) => setState(() => _turnSeconds = v),
                ),
                final BudgetConfig c => _BudgetPanel(
                  config: c,
                  budgetSeconds: _budgetSeconds,
                  incrementSeconds: _incrementSeconds,
                  onBudgetChanged: (v) => setState(() => _budgetSeconds = v),
                  onIncrementChanged: (v) =>
                      setState(() => _incrementSeconds = v),
                ),
              },

              // ── Game-specific config ──────────────────────────────────
              if (_creationConfigWidget != null) ...[
                const SizedBox(height: 16),
                _creationConfigWidget!,
              ],

              // ── Rated toggle ──────────────────────────────────────────
              // Always shown; server silently overrides to unrated if the game
              // type doesn't support rating for this configuration.
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rated'),
                value: _rated,
                onChanged: (v) => setState(() => _rated = v),
              ),

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

  String _timingMode() => switch (_spec.timingConfigs[_timingKey]!) {
    UntimedConfig() => 'untimed',
    PerActionConfig() => 'per_action',
    BudgetConfig() => 'budget',
  };

  Future<void> _createGame() async {
    setState(() => _isLoading = true);
    try {
      final config = _spec.timingConfigs[_timingKey]!;
      int? turnSeconds;
      int? budgetSeconds;
      int? incrementSeconds;
      switch (config) {
        case UntimedConfig():
          break;
        case PerActionConfig():
          turnSeconds = _turnSeconds.round();
        case BudgetConfig():
          budgetSeconds = _budgetSeconds.round();
          incrementSeconds = _incrementSeconds.round();
      }

      final gameId = await ref
          .read(gameRepositoryProvider)
          .createGame(
            access: _access,
            turnSeconds: turnSeconds,
            budgetSeconds: budgetSeconds,
            incrementSeconds: incrementSeconds,
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
            timingMode: _timingMode(),
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

// ── Per-action timing panel ──────────────────────────────────────────────────

class _PerActionPanel extends StatelessWidget {
  const _PerActionPanel({
    required this.config,
    required this.value,
    required this.onChanged,
  });

  final PerActionConfig config;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (config.presets.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: config.presets.map((p) {
              return ChoiceChip(
                label: Text(_formatDuration(p)),
                selected: value.round() == p,
                onSelected: (_) => onChanged(p.toDouble()),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
        ],
        Slider(
          min: config.minSeconds.toDouble(),
          max: config.maxSeconds.toDouble(),
          value: value.clamp(
            config.minSeconds.toDouble(),
            config.maxSeconds.toDouble(),
          ),
          divisions: _sliderDivisions(config.minSeconds, config.maxSeconds),
          onChanged: onChanged,
        ),
        Center(
          child: Text(
            '${_formatDuration(value.round())} per turn',
            style: textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

// ── Budget timing panel ──────────────────────────────────────────────────────

class _BudgetPanel extends StatelessWidget {
  const _BudgetPanel({
    required this.config,
    required this.budgetSeconds,
    required this.incrementSeconds,
    required this.onBudgetChanged,
    required this.onIncrementChanged,
  });

  final BudgetConfig config;
  final double budgetSeconds;
  final double incrementSeconds;
  final ValueChanged<double> onBudgetChanged;
  final ValueChanged<double> onIncrementChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasIncrementRange =
        config.maxIncrementSeconds > config.minIncrementSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preset pairs — each chip sets both sliders.
        if (config.presets.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: config.presets.map((p) {
              final label = p.increment > 0
                  ? '${_formatDuration(p.budget)}+${p.increment}s'
                  : _formatDuration(p.budget);
              return ChoiceChip(
                label: Text(label),
                selected:
                    budgetSeconds.round() == p.budget &&
                    incrementSeconds.round() == p.increment,
                onSelected: (_) {
                  onBudgetChanged(p.budget.toDouble());
                  onIncrementChanged(p.increment.toDouble());
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // Bank slider.
        Text('Bank', style: textTheme.labelMedium),
        Slider(
          min: config.minBudgetSeconds.toDouble(),
          max: config.maxBudgetSeconds.toDouble(),
          value: budgetSeconds.clamp(
            config.minBudgetSeconds.toDouble(),
            config.maxBudgetSeconds.toDouble(),
          ),
          divisions: _sliderDivisions(
            config.minBudgetSeconds,
            config.maxBudgetSeconds,
          ),
          onChanged: onBudgetChanged,
        ),
        Center(
          child: Text(
            _formatDuration(budgetSeconds.round()),
            style: textTheme.bodySmall,
          ),
        ),

        // Increment slider — only when the range is non-trivial.
        if (hasIncrementRange) ...[
          const SizedBox(height: 8),
          Text('Increment', style: textTheme.labelMedium),
          Slider(
            min: config.minIncrementSeconds.toDouble(),
            max: config.maxIncrementSeconds.toDouble(),
            value: incrementSeconds.clamp(
              config.minIncrementSeconds.toDouble(),
              config.maxIncrementSeconds.toDouble(),
            ),
            divisions: config.maxIncrementSeconds - config.minIncrementSeconds,
            onChanged: onIncrementChanged,
          ),
          Center(
            child: Text(
              '${incrementSeconds.round()}s per move',
              style: textTheme.bodySmall,
            ),
          ),
        ] else if (config.minIncrementSeconds > 0) ...[
          // Fixed increment — show as a label, no slider needed.
          const SizedBox(height: 4),
          Center(
            child: Text(
              '+ ${config.minIncrementSeconds}s per move',
              style: textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Number of discrete steps for a slider spanning [min]–[max] seconds.
int _sliderDivisions(int min, int max) {
  final range = max - min;
  if (range <= 300) return range ~/ 30;
  if (range <= 7200) return range ~/ 60;
  if (range <= 86400) return range ~/ 1800;
  return range ~/ 3600;
}

/// Human-readable duration string: "30s", "5m", "2h 30m", "1d".
String _formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }
  if (seconds < 86400) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
  return '${seconds ~/ 86400}d';
}
