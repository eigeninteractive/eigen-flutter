/// The one file an app points at to become a game.
///
/// [RpsModule] is the version-independent container: the registry of
/// [GameRules] units, plus the creation and About UI. Everything that depends
/// on a `schemaVersion` lives in a unit under `v1/`; nothing here branches on
/// version, because creation always targets the newest.
library;

import 'package:eigen_flutter/eigen_flutter.dart';
import 'package:flutter/material.dart';

import 'v1/rules.dart';

/// Rock–Paper–Scissors.
class RpsModule extends GameModule {
  const RpsModule();

  /// One entry today. A breaking rules change adds `2: RpsRulesV2()` and keeps
  /// this one until every v1 match has drained; infra picks the unit from the
  /// match's own `schemaVersion`, so both generations play side by side.
  @override
  Map<int, GameRules> get versions => const {1: RpsRulesV1()};

  @override
  GameCreationSpec get creationSpec => const GameCreationSpec(
    minPlayers: 2,
    maxPlayers: 2,
    // Keys become the segment labels in the new-game dialog, in this order,
    // and the first is selected by default. A per-action clock suits RPS:
    // there is exactly one decision per round and no reason to bank time.
    timingConfigs: {
      'Per move': PerActionConfig(maxSeconds: 300, presets: [30, 60, 120]),
      'Untimed': UntimedConfig(),
    },
    defaultConfig: {'targetWins': 3},
  );

  @override
  Widget? buildCreationConfig({
    required ValueChanged<Map<String, dynamic>> onChanged,
  }) => _TargetWinsPicker(onChanged: onChanged);

  @override
  Widget buildRules(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How to play', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Both players throw at the same time. Rock blunts scissors, '
          'scissors cut paper, paper covers rock. Matching throws draw the '
          'round and nobody scores.',
        ),
        const SizedBox(height: 16),
        Text('Winning', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'The first player to reach the target number of round wins takes '
          'the match. Drawn rounds are replayed and do not count.',
        ),
        const SizedBox(height: 16),
        Text('The clock', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'On a timed match, a player who lets the clock run out forfeits. If '
          'both run out in the same round, the match is drawn.',
        ),
      ],
    );
  }
}

/// The only setting RPS has. Whatever this reports is sent as the game's
/// `config` at creation and arrives back as [RpsV1Config] for the match's whole
/// life: the server validates it against the TS `configSchema`, so an
/// out-of-range value is rejected there, not trusted from here.
class _TargetWinsPicker extends StatefulWidget {
  const _TargetWinsPicker({required this.onChanged});

  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_TargetWinsPicker> createState() => _TargetWinsPickerState();
}

class _TargetWinsPickerState extends State<_TargetWinsPicker> {
  static const _options = [1, 3, 5];
  int _targetWins = 3;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Match length', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: [
            for (final wins in _options)
              ButtonSegment(value: wins, label: Text('First to $wins')),
          ],
          selected: {_targetWins},
          onSelectionChanged: (selection) {
            setState(() => _targetWins = selection.first);
            widget.onChanged({'targetWins': _targetWins});
          },
        ),
      ],
    );
  }
}
