import 'package:flutter/material.dart';
import 'package:eigen_engine/core/game/game_creation_spec.dart';

/// Timing values resolved from a [TimingSelector], ready for the create RPCs.
typedef ResolvedTiming = ({
  String mode, // 'untimed' | 'per_action' | 'budget'
  int? turnSeconds,
  int? budgetSeconds,
  int? incrementSeconds,
});

/// Timing-mode picker shared by the New Game and Play-vs-AI dialogs.
///
/// Renders the "Timing" header, a mode selector (only when the game offers more
/// than one mode), and the per-mode sliders/presets. Owns its own slider state
/// and reports the resolved values via [onChanged]. Seed a parent's state with
/// [TimingSelector.initial] so there is no null window before the first change.
class TimingSelector extends StatefulWidget {
  const TimingSelector({
    super.key,
    required this.configs,
    required this.onChanged,
    this.enabled = true,
    this.initialKey,
  });

  final Map<String, TimingModeConfig> configs;
  final ValueChanged<ResolvedTiming> onChanged;
  final bool enabled;

  /// The mode to select initially (a key of [configs]). `null` or an unknown key
  /// falls back to the first declared mode. Lets a caller that knows more than
  /// this widget — e.g. the solo picker, which inspects the bot catalog — open it
  /// in a mode that actually has opponents, without coupling this widget to bots.
  final String? initialKey;

  /// The resolved timing for the initial selection — matching what the widget
  /// would emit before any interaction, so a parent can seed its state without a
  /// null window. Pass the same [initialKey] used on the widget.
  static ResolvedTiming initial(
    Map<String, TimingModeConfig> configs, {
    String? initialKey,
  }) {
    final config = configs[_resolveKey(configs, initialKey)]!;
    final (turn, budget, increment) = _defaults(config);
    return _resolve(config, turn, budget, increment);
  }

  @override
  State<TimingSelector> createState() => _TimingSelectorState();
}

class _TimingSelectorState extends State<TimingSelector> {
  late String _key;
  late double _turnSeconds;
  late double _budgetSeconds;
  late double _incrementSeconds;

  @override
  void initState() {
    super.initState();
    _key = _resolveKey(widget.configs, widget.initialKey);
    _applyDefaults(widget.configs[_key]!);
  }

  void _applyDefaults(TimingModeConfig config) {
    final (turn, budget, increment) = _defaults(config);
    _turnSeconds = turn;
    _budgetSeconds = budget;
    _incrementSeconds = increment;
  }

  void _emit() => widget.onChanged(
    _resolve(
      widget.configs[_key]!,
      _turnSeconds,
      _budgetSeconds,
      _incrementSeconds,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final configs = widget.configs;
    final selected = configs[_key]!;

    // Nothing to choose when the game offers only untimed play (the default
    // spec) — don't render a lone "Timing" header with no control under it.
    if (configs.length == 1 && selected is UntimedConfig) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Timing', style: textTheme.labelLarge),
        const SizedBox(height: 8),
        if (configs.length > 1) ...[
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: configs.keys
                .map((k) => ButtonSegment(value: k, label: Text(k)))
                .toList(),
            selected: {_key},
            onSelectionChanged: widget.enabled
                ? (s) => setState(() {
                    _key = s.first;
                    _applyDefaults(configs[_key]!);
                    _emit();
                  })
                : null,
          ),
          const SizedBox(height: 12),
        ],
        switch (selected) {
          UntimedConfig() => const SizedBox.shrink(),
          final PerActionConfig c => _PerActionPanel(
            config: c,
            value: _turnSeconds,
            enabled: widget.enabled,
            onChanged: (v) => setState(() {
              _turnSeconds = v;
              _emit();
            }),
          ),
          final BudgetConfig c => _BudgetPanel(
            config: c,
            budgetSeconds: _budgetSeconds,
            incrementSeconds: _incrementSeconds,
            enabled: widget.enabled,
            onBudgetChanged: (v) => setState(() {
              _budgetSeconds = v;
              _emit();
            }),
            onIncrementChanged: (v) => setState(() {
              _incrementSeconds = v;
              _emit();
            }),
          ),
        },
      ],
    );
  }
}

/// [initialKey] if it names a real mode, otherwise the first declared mode.
String _resolveKey(Map<String, TimingModeConfig> configs, String? initialKey) {
  if (initialKey != null && configs.containsKey(initialKey)) return initialKey;
  return configs.keys.first;
}

/// Default `(turn, budget, increment)` seconds for [config]'s mode.
(double, double, double) _defaults(TimingModeConfig config) => switch (config) {
  UntimedConfig() => (
    kMinTurnSeconds.toDouble(),
    kMinBudgetSeconds.toDouble(),
    0,
  ),
  PerActionConfig(:final presets, :final minSeconds) => (
    (presets.isNotEmpty ? presets.first : minSeconds).toDouble(),
    kMinBudgetSeconds.toDouble(),
    0,
  ),
  BudgetConfig(
    :final presets,
    :final minBudgetSeconds,
    :final minIncrementSeconds,
  ) =>
    (
      kMinTurnSeconds.toDouble(),
      presets.isNotEmpty
          ? presets.first.budget.toDouble()
          : minBudgetSeconds.toDouble(),
      presets.isNotEmpty
          ? presets.first.increment.toDouble()
          : minIncrementSeconds.toDouble(),
    ),
};

/// Resolves the per-mode slider values into the timing the create RPCs expect.
ResolvedTiming _resolve(
  TimingModeConfig config,
  double turn,
  double budget,
  double increment,
) => switch (config) {
  UntimedConfig() => (
    mode: 'untimed',
    turnSeconds: null,
    budgetSeconds: null,
    incrementSeconds: null,
  ),
  PerActionConfig() => (
    mode: 'per_action',
    turnSeconds: turn.round(),
    budgetSeconds: null,
    incrementSeconds: null,
  ),
  BudgetConfig() => (
    mode: 'budget',
    turnSeconds: null,
    budgetSeconds: budget.round(),
    incrementSeconds: increment.round(),
  ),
};

// ── Per-action timing panel ──────────────────────────────────────────────────

class _PerActionPanel extends StatelessWidget {
  const _PerActionPanel({
    required this.config,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final PerActionConfig config;
  final double value;
  final bool enabled;
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
                onSelected: enabled ? (_) => onChanged(p.toDouble()) : null,
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
          onChanged: enabled ? onChanged : null,
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
    required this.enabled,
    required this.onBudgetChanged,
    required this.onIncrementChanged,
  });

  final BudgetConfig config;
  final double budgetSeconds;
  final double incrementSeconds;
  final bool enabled;
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
                onSelected: enabled
                    ? (_) {
                        onBudgetChanged(p.budget.toDouble());
                        onIncrementChanged(p.increment.toDouble());
                      }
                    : null,
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
          onChanged: enabled ? onBudgetChanged : null,
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
            onChanged: enabled ? onIncrementChanged : null,
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
