import 'package:flutter/material.dart';
import 'package:eigen_flutter/core/game/game_creation_spec.dart';
import 'package:eigen_flutter/core/game/game_frame.dart';
import 'package:eigen_flutter/core/game/my_seat.dart';
import 'package:eigen_flutter/core/game/players_context.dart';
import 'package:eigen_flutter/core/game/timing_context.dart';
import 'package:eigen_api/eigen_api.dart' show GameAccess, GameStatus, Outcome;

/// How a submitted action resolved, reported to the game through the future
/// returned by [GameContentContext.onAction].
///
/// The three values carry exactly the distinction an optimistic game needs:
/// whether a confirming frame is coming ([committed]), definitely not coming
/// ([rejected]), or unknown ([unconfirmed]). A game with no optimistic
/// rendering can ignore the result entirely.
enum ActionSubmitResult {
  /// The server committed the action. Its confirming frame is the *next*
  /// frame this seat receives — the optimistic lock guarantees no other
  /// frame can land in between.
  committed,

  /// The action definitively did not commit: the server rejected it, or it
  /// was never sent (another submit was already in flight). Infra has
  /// already surfaced any error to the player; revert optimistic rendering —
  /// no frame will arrive for this action.
  rejected,

  /// The submission failed in transit and the outcome is unknown — the
  /// server may still have committed it. Revert optimistic rendering; if the
  /// action did commit, its frame arrives over the game socket and re-applies
  /// the move.
  unconfirmed,
}

/// Everything [GameRules.buildContent] needs, bundled into one object.
///
/// Passing a single context (instead of a long parameter list) means adding a
/// new piece of infra data later does not change the [GameRules.buildContent]
/// signature — and therefore does not force every game to update. Redundant
/// values ([mySeat], [timing]) are exposed as getters that delegate to
/// the authoritative source so there is only ever one of each.
///
/// The two halves of the live game are kept separate: [config] is parsed once
/// from the immutable game config and lives for the whole game; [frame] is the
/// per-event observation snapshot. Cast [config] and `frame.observation` to
/// your concrete types (e.g. `config as StrategyConfigData`).
class GameContentContext {
  const GameContentContext({
    required this.config,
    required this.frame,
    required this.gameStatus,
    required this.outcomes,
    required this.actionPending,
    required this.onAction,
    required this.onInvalidAction,
    required this.playersContext,
    this.isReplay = false,
  });

  /// The game's parsed config ([GameRules.parseConfig] of `games.config`),
  /// immutable for the whole game. Cast to your concrete config type.
  final Object config;

  /// The current observation snapshot: parsed observation, version, pending
  /// players and timing. Rebuilt on every observation event.
  final GameFrame frame;

  /// Current lifecycle status of the game.
  final GameStatus gameStatus;

  /// Per-participant outcomes. Empty while the game is active; populated once
  /// it finishes.
  final List<Outcome> outcomes;

  /// True while a submitted action awaits its confirming observation. Disable
  /// input on this to prevent double-submission.
  final bool actionPending;

  /// Submits a game action (as JSON) through infra.
  ///
  /// The returned future resolves with how the submit ended (see
  /// [ActionSubmitResult] for what each value guarantees about the frame
  /// stream); it never throws, and infra has already surfaced any error to
  /// the player before it resolves. Games that render purely from server
  /// frames may ignore the result — fire-and-forget remains the simplest
  /// correct usage.
  final Future<ActionSubmitResult> Function(Map<String, dynamic> actionJson)
  onAction;

  /// Call when the engine rejects a move client-side. Infra owns the haptic.
  final VoidCallback onInvalidAction;

  /// Resolved player identities, keyed by seat index.
  final PlayersContext playersContext;

  /// True when the frame is being shown in replay (a finished game stepped
  /// through frame by frame), false during live play.
  ///
  /// [frame] is a historical snapshot and [onAction] is inert, so a game
  /// never needs this to stay correct — it disables input off the pending set
  /// as usual. Use it only for replay-specific presentation, e.g. surfacing
  /// move-by-move narration or suppressing "your turn" prompts. When [mySeat]
  /// is a [Viewer] the current user did not play in the game (a public replay
  /// opened by a non-participant), which only happens in replay.
  final bool isReplay;

  /// The current user's place in the game: [Seated] at an index, or a [Viewer]
  /// (no seat — only when replaying a public game they did not play in).
  MySeat get mySeat => playersContext.mySeat;

  /// Timing metadata for the current turn (mirrors [GameFrame.timing]).
  TimingContext get timing => frame.timing;
}

/// The chosen game settings, passed to [GameRules.ratingPool].
///
/// Field-for-field twin of the TS `RatingPoolArgs` interface — same names,
/// same types — so the Dart and TS `ratingPool` implementations read
/// identically and stay trivially diffable.
class RatingPoolArgs {
  const RatingPoolArgs({
    required this.access,
    this.turnSeconds,
    this.budgetSeconds,
    this.incrementSeconds,
    required this.minPlayers,
    required this.maxPlayers,
    required this.config,
  });

  final GameAccess access;
  final int? turnSeconds;
  final int? budgetSeconds;
  final int? incrementSeconds;
  final int minPlayers;
  final int maxPlayers;
  final Map<String, dynamic> config;
}

/// A candidate bot seating, passed to [GameRules.botSeatable].
///
/// Field-for-field twin of the TS `BotSeatableArgs` interface. [gameConfig]
/// is the game's creation config; [botConfig] is the bot's declared
/// capabilities (`bots.config`) — game-owned but unversioned, so it stays an
/// opaque map.
class BotSeatableArgs {
  const BotSeatableArgs({required this.gameConfig, required this.botConfig});

  final Map<String, dynamic> gameConfig;
  final Map<String, dynamic> botConfig;
}

/// The client-side surface of one `schemaVersion` of the game — the Dart
/// twin of the same-named TS `GameRules` unit.
///
/// A version unit is self-contained: it parses and renders exactly one
/// generation of payload shapes, so nothing in it ever branches on version.
/// When rules or shapes change incompatibly, ship a new subclass under the
/// next key in [GameModule.versions] (reusing unchanged widgets/logic by
/// import) instead of branching inside this one. Games created under an old
/// version keep loading through their own unit until they drain.
///
/// The TS unit owns the authoritative hooks (`initialState`, `applyAction`,
/// `applyLifecycle`, `computeObservation`) plus the Zod `schemas`; this side
/// owns the client half, member for member:
///
/// - the generated payload parsing and serialization ([parseConfig] /
///   [parseObservation] / [parseAction] / [serializeAction]) — emitted from
///   the TS schemas;
/// - [isValidAction] — the legality half of the TS `applyAction`, transcribed;
/// - [previewAction] — the game's own optimistic projection of `applyAction`
///   (a standardized contract; infra never calls it);
/// - rendering ([buildContent]);
/// - display-only twins of the two predicates ([ratingPool] / [botSeatable]).
///
/// Keep the twins in sync with the TS unit for the same version — the server
/// recomputes everything authoritative, so drift only degrades UX, never
/// stored data.
///
/// The type parameters are this version's payload types. Infra holds units
/// erased (`Map<int, GameRules>` on the module) and calls through the erased
/// type; your own code (widgets, bots) works against the concrete subclass.
///
/// `eigen_flutter:generate_payloads` emits a typed abstract base class that
/// implements the four JSON methods below. Game implementations extend that
/// generated base and only supply game behavior.
abstract class GameRules<TObs, TAction, TConfig> {
  const GameRules();

  /// Parses the raw `games.config` JSON into this version's config type.
  ///
  /// Called once per game by infra (the parsed value is cached and handed to
  /// [buildContent] via [GameContentContext.config]).
  TConfig parseConfig(Map<String, dynamic> json);

  /// Parses a raw observation JSON map into this version's observation type.
  ///
  /// Called once per network event — never on frame rebuild.
  TObs parseObservation(Map<String, dynamic> json);

  /// Parses a raw action JSON map into this version's action type — the input
  /// mirror of [serializeAction] (the TS twin's `schemas.action` covers both
  /// directions). Infra uses it to re-type a logged action (e.g. for replay
  /// cues).
  TAction parseAction(Map<String, dynamic> json);

  /// Serialises a typed action into the JSON map submitted to the server.
  ///
  /// Infra holds rules units erased and cannot call a concrete `toJson`, so
  /// the unit owns this serialization step. The returned map is the action
  /// `data` the TS `applyAction` hook consumes — identical whether the move
  /// came from a human tap, a local bot, or a server bot, because every
  /// producer routes through this one seam.
  Map<String, dynamic> serializeAction(TAction action);

  /// Validates local legality of an action for client-side UX feedback.
  ///
  /// The authoritative check runs server-side in the TS `applyAction` hook;
  /// this is for disabling illegal taps and similar — essentially the
  /// legality half of that hook, transcribed. The parameter names
  /// deliberately match the TS `ApplyActionArgs` fields (`pending`, `data`,
  /// `playerIndex`, `config`) so the two read side by side. All parameters
  /// are passed to every game so the contract stays uniform across turn
  /// styles; simple games can ignore whatever they don't need.
  ///
  /// - [obs]: the current typed game payload (board, hand, fog, ...).
  /// - [pending]: 0-based indices whose "main turn" is active right now —
  ///   this seat's projection of `game_states.pending_players`, from its
  ///   observation row. Games with interrupt actions (e.g. Exploding
  ///   Kittens's Nope) use this to distinguish a main-turn action from an
  ///   interrupt (anyone holding the card may play).
  /// - [data]: the candidate action payload.
  /// - [playerIndex]: the 0-based index of the player attempting [data].
  ///   For games where piece ownership matters (Chess — only your color),
  ///   this identifies the actor; sequential games that don't care can
  ///   ignore it.
  /// - [config]: this game's parsed config.
  bool isValidAction({
    required TObs obs,
    required List<int> pending,
    required TAction data,
    required int playerIndex,
    required TConfig config,
  });

  /// Predicts this seat's next observation for [data], or returns null when
  /// the outcome depends on hidden information (a combat resolution, a
  /// reveal, a draw from a deck) — that move is then simply server-driven.
  ///
  /// **Infra never calls this.** It is required anyway so every game states
  /// its optimism contract explicitly in one standard place, instead of each
  /// game inventing its own prediction shape inside widget code. A game that
  /// wants optimistic rendering calls it from its own widgets, pairing the
  /// predicted observation with the [GameContentContext.onAction] result
  /// (`false` → revert; `true` → the next frame is the confirming one). A
  /// game that wants every move server-driven returns null unconditionally —
  /// always correct.
  ///
  /// Keeping the signature standardized (parameters mirror [isValidAction])
  /// also leaves the door open to engine-level wiring later without an API
  /// change. A prediction is for the actor's own moves only and is
  /// display-only: it must never feed back into submitted state or the
  /// optimistic-lock version.
  TObs? previewAction({
    required TObs obs,
    required List<int> pending,
    required TAction data,
    required int playerIndex,
    required TConfig config,
  });

  /// Renders the in-game content.
  ///
  /// All JSON parsing is done before this call: [GameContentContext.config]
  /// carries the parsed config and [GameContentContext.frame] the parsed
  /// observation (`frame.observation` is guaranteed non-null when called from
  /// [game_screen.dart]). Cast both to your concrete types once, at the top.
  ///
  /// [GameContentContext.onInvalidAction] is provided by infra and should be
  /// called when the game rejects a move client-side ([isValidAction]
  /// returning false). Infra wires it to [HapticFeedback.selectionClick];
  /// game implementors do not choose the haptic.
  Widget buildContent(GameContentContext context);

  /// The rating pool a game with these settings would fall into, or `null` if
  /// it is unrated (casual). Drives the create dialog: the Rated toggle is
  /// shown only when this returns non-null. **Display only** — the server
  /// recomputes the authoritative pool (the TS `GameRules.ratingPool` twin) at
  /// creation and a guest is always forced unrated, so a wrong value here only
  /// affects the UI, never the stored rating.
  String? ratingPool(RatingPoolArgs args);

  /// Whether a bot whose declared capabilities are [BotSeatableArgs.botConfig]
  /// can play a game with [BotSeatableArgs.gameConfig]. Used to filter the bot
  /// pickers locally (no network call). **UX only** — the server enforces the
  /// same rule (the TS `GameRules.botSeatable` twin) before seating.
  bool botSeatable(BotSeatableArgs args);
}

/// Contract every game implementor provides.
///
/// **Extend** (don't implement) this in the game package's `game_module.dart`
/// (e.g. `games/tic_tac_toe/lib/game_module.dart`) — that is the single file to
/// edit when swapping games, and extending inherits the default
/// [playersForConfig]. Register the implementation via
/// `currentGameModuleProvider.overrideWithValue(...)` in the app's `main.dart`.
///
/// The module is a thin container — the same-named twin of the TS
/// `GameModule`: the version registry ([versions], one [GameRules] unit per
/// `schemaVersion`) plus the creation/about UI, which is version-independent
/// because creation always targets [latestSchemaVersion]. All version
/// dispatch is owned by infra — game code never branches on version.
abstract class GameModule {
  const GameModule();

  /// The [GameRules] units keyed by `schemaVersion` — exactly the versions
  /// this build ships, mirroring the keys of the TS `GameModule.versions`.
  ///
  /// Sparse on purpose: loading a game requires its version's entry
  /// ([supportsSchema]), new games are created at the highest key
  /// ([latestSchemaVersion]), and a drained old version is retired by
  /// deleting its entry. A brand-new game starts at `{1: ...}`.
  ///
  /// Bump when shipping a breaking rules/schema change, keeping the old
  /// entry until those games drain (write) / stop being replayable (read).
  Map<int, GameRules> get versions;

  /// The version new games are created at — the highest key of [versions] —
  /// and the value sent as `p_client_schema_version` on join/create.
  int get latestSchemaVersion => versions.keys.reduce((a, b) => a > b ? a : b);

  /// The rules unit new games use ([versions] at [latestSchemaVersion]).
  GameRules get latestRules => versions[latestSchemaVersion]!;

  /// Whether this build can load a game created at [version] — i.e. [versions]
  /// ships an entry for it. Sparse like the TS side: an old version dropped
  /// after draining is unsupported even if lower than [latestSchemaVersion].
  bool supportsSchema(int version) => versions.containsKey(version);

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
  /// upfront, then sets min = max = chosen count so joining flips the game to
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
  /// displayed in the UI) and sends it with the create-game request at submit
  /// time.
  Widget? buildCreationConfig({
    required ValueChanged<Map<String, dynamic>> onChanged,
  });

  /// Game-supplied rules / how-to-play content for the About page.
  ///
  /// Return plain, non-scrolling content (e.g. a [Column] of sections); the
  /// About page provides the scroll container, padding and app-level chrome.
  /// Free to be interactive (animated board examples) and to read [Theme.of].
  Widget buildRules(BuildContext context);
}

/// Thrown when a game's `games.schema_version` has no entry in
/// [GameModule.versions] — it was created by a newer app version (or one this
/// build has retired) and can't be loaded until the user updates.
class UnsupportedGameSchemaException implements Exception {
  const UnsupportedGameSchemaException({
    required this.gameSchema,
    required this.supportedSchema,
  });

  /// The game's `schemaVersion` (from the server).
  final int gameSchema;

  /// The latest schema this build supports ([GameModule.latestSchemaVersion]).
  final int supportedSchema;

  @override
  String toString() =>
      'UnsupportedGameSchemaException: no rules for game schema $gameSchema '
      '(latest supported: $supportedSchema) — the app must be updated.';
}
