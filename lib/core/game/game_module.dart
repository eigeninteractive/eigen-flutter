import 'package:flutter/material.dart';
import 'package:eigen_engine/core/game/base_engine.dart';
import 'package:eigen_engine/core/game/game_creation_spec.dart';
import 'package:eigen_engine/core/game/game_frame.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/core/game/game_status.dart';
import 'package:eigen_engine/core/game/players_context.dart';
import 'package:eigen_engine/core/game/timing_context.dart';

/// Everything [GameModule.buildContent] needs, bundled into one object.
///
/// Passing a single context (instead of a long parameter list) means adding a
/// new piece of infra data later does not change the [GameModule.buildContent]
/// signature — and therefore does not force every game to update. Redundant
/// values ([myPlayerIndex], [timing]) are exposed as getters that delegate to
/// the authoritative source so there is only ever one of each.
///
/// The two halves of the live game are kept separate: [engine] is created once
/// from the immutable config and lives for the whole game; [frame] is the
/// per-event observation snapshot. Cast [engine] and `frame.observation` to
/// your concrete types (e.g. `engine as TicTacToeEngine`).
class GameContentContext {
  const GameContentContext({
    required this.engine,
    required this.frame,
    required this.gameStatus,
    required this.outcomes,
    required this.actionPending,
    required this.onAction,
    required this.onInvalidAction,
    required this.playersContext,
  });

  /// The game's engine, created once from immutable config.
  final BaseEngine engine;

  /// The current observation snapshot: parsed observation, version, pending
  /// players and timing. Rebuilt on every observation event.
  final GameFrame frame;

  /// Current lifecycle status of the game.
  final GameStatus gameStatus;

  /// Per-participant outcomes. Empty while the game is active; populated once
  /// it finishes.
  final List<GameOutcome> outcomes;

  /// True while a submitted action awaits its confirming observation. Disable
  /// input on this to prevent double-submission.
  final bool actionPending;

  /// Submits a game action (as JSON) through infra.
  final void Function(Map<String, dynamic> actionJson) onAction;

  /// Call when the engine rejects a move client-side. Infra owns the haptic.
  final VoidCallback onInvalidAction;

  /// Resolved player identities, keyed by seat index.
  final PlayersContext playersContext;

  /// The current user's seat index, or -1 if spectating.
  int get myPlayerIndex => playersContext.myPlayerIndex;

  /// Timing metadata for the current turn (mirrors [GameFrame.timing]).
  TimingContext get timing => frame.timing;
}

/// Contract every game implementor provides.
///
/// **Extend** (don't implement) this in the game package's `game_module.dart`
/// (e.g. `games/tic_tac_toe/lib/game_module.dart`) — that is the single file to
/// edit when swapping games, and extending inherits the default
/// [playersForConfig]. Register the implementation via
/// `currentGameModuleProvider.overrideWithValue(...)` in the app's `main.dart`.
abstract class GameModule {
  const GameModule();

  /// Declarative description of valid creation parameters for this game type.
  ///
  /// Read by [NewGameDialog] to render only the controls that apply.
  /// [GameCreationSpec.timingConfigs] keys become [SegmentedButton] labels;
  /// values declare the valid range and optional presets for each mode.
  /// [GameCreationSpec.defaultConfig] seeds the config before the player
  /// interacts with [buildCreationConfig].
  GameCreationSpec get creationSpec;

  /// Returns the `(minPlayers, maxPlayers)` pair for the given game config.
  ///
  /// Override when valid player counts depend on a config choice made at
  /// creation time (e.g. a game supporting 4 or 6 players lets the host pick
  /// upfront, then sets min = max = chosen count so [join_game] flips to
  /// `ready` at exactly the right threshold).
  ///
  /// The default returns [creationSpec.minPlayers] and [creationSpec.maxPlayers].
  (int min, int max) playersForConfig(Map<String, dynamic> config) =>
      (creationSpec.minPlayers, creationSpec.maxPlayers);

  /// Optional widget for game-specific creation config (board size, variants…).
  ///
  /// Return null if the game has no config beyond timing and player count.
  ///
  /// [onChanged] is called whenever the player adjusts a setting. The dialog
  /// stores the latest value in a plain field (not state — it is never
  /// displayed in the UI) and passes it to [create_game] at submit time.
  Widget? buildCreationConfig({
    required ValueChanged<Map<String, dynamic>> onChanged,
  });

  /// Creates (and configures) the engine from raw config JSON.
  ///
  /// Called once per config change by [gameEngineProvider], not per frame.
  BaseEngine createEngine(Map<String, dynamic> configJson);

  /// Renders the in-game content.
  ///
  /// All JSON parsing is done before this call. [GameContentContext.engine]
  /// is the typed engine and [GameContentContext.frame] carries the parsed
  /// observation; `frame.observation` is guaranteed non-null when called from
  /// [game_screen.dart].
  ///
  /// [GameContentContext.onInvalidAction] is provided by infra and should be
  /// called when the game rejects a move client-side (e.g.
  /// [BaseEngine.isValidAction] returns false). Infra wires it to
  /// [HapticFeedback.selectionClick]; game implementors do not choose the
  /// haptic.
  Widget buildContent(GameContentContext context);
}
