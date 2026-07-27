import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:eigen_flutter/core/game/game_creation_spec.dart';
import 'package:eigen_flutter/core/game/game_module.dart';
import 'package:eigen_api/eigen_api.dart' show GameAccess;

/// Minimal tic-tac-toe-like observation: a flat board of 9 cells where each
/// entry is the occupying player index, or null if empty.
///
/// Value equality (like a Freezed model's) so twin-fixture preview
/// comparisons can use `==`.
class SampleObservation {
  const SampleObservation(this.board);

  factory SampleObservation.fromJson(Map<String, dynamic> json) =>
      SampleObservation((json['board'] as List).map((e) => e as int?).toList());

  final List<int?> board;

  Map<String, dynamic> toJson() => {'board': board};

  @override
  bool operator ==(Object other) =>
      other is SampleObservation && listEquals(other.board, board);

  @override
  int get hashCode => Object.hashAll(board);
}

/// Candidate move: place a mark in [cell].
class SampleAction {
  const SampleAction(this.cell);

  factory SampleAction.fromJson(Map<String, dynamic> json) =>
      SampleAction(json['cell'] as int);

  final int cell;

  Map<String, dynamic> toJson() => {'cell': cell};
}

/// No per-instance configuration for the sample game.
class SampleConfig {
  const SampleConfig();
}

/// The schema-version-1 rules unit of the sample game.
///
/// Real games inherit these JSON methods from their generated rules base. This
/// handwritten test fixture implements them directly so it has no generated
/// artifact.
class SampleRules
    extends GameRules<SampleObservation, SampleAction, SampleConfig> {
  const SampleRules();

  @override
  SampleConfig parseConfig(Map<String, dynamic> json) => const SampleConfig();

  @override
  SampleObservation parseObservation(Map<String, dynamic> json) =>
      SampleObservation.fromJson(json);

  @override
  SampleAction parseAction(Map<String, dynamic> json) =>
      SampleAction.fromJson(json);

  @override
  Map<String, dynamic> serializeAction(SampleAction action) => action.toJson();

  @override
  bool isValidAction({
    required SampleObservation obs,
    required List<int> pending,
    required SampleAction data,
    required int playerIndex,
    required SampleConfig config,
  }) {
    if (!pending.contains(playerIndex)) return false;
    if (data.cell < 0 || data.cell >= obs.board.length) return false;
    return obs.board[data.cell] == null;
  }

  @override
  SampleObservation? previewAction({
    required SampleObservation obs,
    required List<int> pending,
    required SampleAction data,
    required int playerIndex,
    required SampleConfig config,
  }) {
    final board = List<int?>.of(obs.board);
    board[data.cell] = playerIndex;
    return SampleObservation(board);
  }

  @override
  Widget buildContent(GameContentContext context) => const SizedBox.shrink();

  @override
  String? ratingPool(RatingPoolArgs args) =>
      args.access == GameAccess.public ? 'casual' : null;

  @override
  bool botSeatable(BotSeatableArgs args) => true;
}

/// A minimal [GameModule] for use as a `currentGameModuleProvider` override.
class SampleModule extends GameModule {
  const SampleModule();

  @override
  Map<int, GameRules> get versions => const {1: SampleRules()};

  @override
  GameCreationSpec get creationSpec =>
      const GameCreationSpec(minPlayers: 2, maxPlayers: 2);

  @override
  Widget? buildCreationConfig({
    required ValueChanged<Map<String, dynamic>> onChanged,
  }) => null;

  @override
  Widget buildRules(BuildContext context) => const Text('Sample rules');
}
