import 'package:flutter/widgets.dart';
import 'package:eigen_engine/core/game/base_engine.dart';
import 'package:eigen_engine/core/game/game_creation_spec.dart';
import 'package:eigen_engine/core/game/game_module.dart';

/// Minimal tic-tac-toe-like observation: a flat board of 9 cells where each
/// entry is the occupying player index, or null if empty.
class SampleObservation {
  const SampleObservation(this.board);

  factory SampleObservation.fromJson(Map<String, dynamic> json) =>
      SampleObservation((json['board'] as List).map((e) => e as int?).toList());

  final List<int?> board;
}

/// Candidate move: place a mark in [cell].
class SampleAction {
  const SampleAction(this.cell);

  final int cell;

  Map<String, dynamic> toJson() => {'cell': cell};
}

/// No per-instance configuration for the sample game.
class SampleConfig {
  const SampleConfig();
}

/// A trivial [BaseEngine] used to exercise and demonstrate the engine contract.
///
/// This is the template downstream games follow: pure, infra-free
/// action-legality logic that a game package can unit-test in isolation.
class SampleEngine
    extends BaseEngine<SampleObservation, SampleAction, SampleConfig> {
  SampleEngine({super.schemaVersion = 1}) : super(const SampleConfig());

  @override
  SampleObservation parseObservation(Map<String, dynamic> json) =>
      SampleObservation.fromJson(json);

  @override
  Map<String, dynamic> serializeAction(SampleAction action) => action.toJson();

  @override
  bool isValidAction(
    SampleObservation obs,
    List<int> pendingPlayers,
    SampleAction action,
    int playerIndex,
  ) {
    if (!pendingPlayers.contains(playerIndex)) return false;
    if (action.cell < 0 || action.cell >= obs.board.length) return false;
    return obs.board[action.cell] == null;
  }
}

/// A minimal [GameModule] for use as a `currentGameModuleProvider` override.
class SampleModule extends GameModule {
  const SampleModule();

  @override
  int get schemaVersion => 1;

  @override
  GameCreationSpec get creationSpec =>
      const GameCreationSpec(minPlayers: 2, maxPlayers: 2);

  @override
  Widget? buildCreationConfig({
    required ValueChanged<Map<String, dynamic>> onChanged,
  }) => null;

  @override
  BaseEngine createEngine(Map<String, dynamic> configJson, int schemaVersion) =>
      SampleEngine();

  @override
  Widget buildContent(GameContentContext context) => const SizedBox.shrink();

  @override
  Widget buildRules(BuildContext context) => const Text('Sample rules');
}
