/// A minimal Dart [GameRules] unit: the trivial one-move game where player 0
/// acts once and wins.
///
/// Exists so the engine can dogfood its own twin-fixture pipeline end to end,
/// this unit runs `test/fixtures/game/v1/` through
/// `lib/testing/twin_fixtures.dart`, exercising the same path a real game's
/// Dart twin takes.
library;

import 'package:flutter/widgets.dart';
import 'package:eigen_flutter/core/game/game_module.dart';

/// The example game's whole observation: how many moves have been made.
class ExampleObservation {
  const ExampleObservation(this.moves);

  factory ExampleObservation.fromJson(Map<String, dynamic> json) =>
      ExampleObservation(json['moves'] as int);

  final int moves;

  @override
  bool operator ==(Object other) =>
      other is ExampleObservation && other.moves == moves;

  @override
  int get hashCode => moves.hashCode;

  @override
  String toString() => 'ExampleObservation(moves: $moves)';
}

/// The example game's action carries no payload (any move wins).
class ExampleAction {
  const ExampleAction();

  factory ExampleAction.fromJson(Map<String, dynamic> _) =>
      const ExampleAction();

  Map<String, dynamic> toJson() => const {};
}

/// The example game has no per-instance configuration.
class ExampleConfig {
  const ExampleConfig();
}

/// Dart twin of the TS `ExampleRulesV1`, member for member.
class ExampleRules
    extends GameRules<ExampleObservation, ExampleAction, ExampleConfig> {
  const ExampleRules();

  @override
  ExampleConfig parseConfig(Map<String, dynamic> json) => const ExampleConfig();

  @override
  ExampleObservation parseObservation(Map<String, dynamic> json) =>
      ExampleObservation.fromJson(json);

  @override
  ExampleAction parseAction(Map<String, dynamic> json) =>
      ExampleAction.fromJson(json);

  @override
  Map<String, dynamic> serializeAction(ExampleAction action) => action.toJson();

  /// The TS `applyAction` never rejects a move, so every action is valid.
  @override
  bool isValidAction({
    required ExampleObservation obs,
    required List<int> pending,
    required ExampleAction data,
    required int playerIndex,
    required ExampleConfig config,
  }) => true;

  /// Mirrors the TS `applyAction` (moves + 1) through its passthrough
  /// observation.
  @override
  ExampleObservation? previewAction({
    required ExampleObservation obs,
    required List<int> pending,
    required ExampleAction data,
    required int playerIndex,
    required ExampleConfig config,
  }) => ExampleObservation(obs.moves + 1);

  @override
  Widget buildContent(GameContentContext context) => const SizedBox.shrink();

  @override
  String? ratingPool(RatingPoolArgs args) => null;

  @override
  bool botSeatable(BotSeatableArgs args) => true;
}
