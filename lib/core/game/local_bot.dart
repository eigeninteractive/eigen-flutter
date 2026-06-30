import 'dart:async';

import 'package:eigen_engine/core/game/base_engine.dart';

/// A local bot: a pure function that computes a bot seat's move, client-side.
///
/// Game-specific logic, so implementations live in the game package (alongside
/// the `GameModule`), not the engine — the engine owns only this contract and
/// the wiring. A local bot is only ever driven in a *solo* game (one human +
/// bot(s)); the engine enforces that and reveals a bot seat's observation to the
/// human's client only when no other human is present.
///
/// ## A pure reducer, run off-thread by the engine
///
/// A bot is a pure function `(observation, state) → (action, nextState)`. The
/// driver holds the seat's committed [TState] and runs [chooseAction] in an
/// **ephemeral isolate** (`Isolate.run`), so a move may take seconds **without
/// blocking a UI frame** — implementors write no isolate code. The flip side is
/// that everything the call touches is copied across the isolate boundary, so:
///
/// - **It (and its inputs/results) must be isolate-sendable** — plain logic and
///   data, no Supabase clients, ports, or `dart:ui` handles in [TState], the
///   bot, or the engine.
/// - **The bot instance and [BaseEngine] are copied in on every call**, so keep
///   them lightweight. A bot needing large static data (a pretrained neural net,
///   big tables) belongs **server-side**, not here — it would be re-shipped into
///   the isolate every move.
///
/// ## State rules
///
/// [chooseAction] **must be pure**: never mutate [TState] or perform side
/// effects. It may be run speculatively and discarded the instant a newer
/// observation supersedes it. The driver commits the returned state **only when
/// its action is accepted** by the server, so:
///
/// - Prefer immutable state with structural sharing (return a new state that
///   shares the unchanged parts).
/// - Any randomness must be seeded from [TState] and the advanced seed returned
///   in the result — never a global RNG — so a re-run is reproducible.
/// - The observation must be a full-enough seat snapshot to advance an
///   accumulated belief from any earlier committed state in one step (true for
///   this engine's seat-view observations — `app_local_bot_observation`), since a
///   rejected/superseded action means the next call resumes from the last
///   *accepted* state against a newer observation.
///
/// Generic over the same `<TObservationData, TActionData, TConfigData>` triple as
/// [BaseEngine], plus [TState] for the bot's private per-(game, seat) brain
/// (client-only — never serialised to the server). Declare it alongside the
/// engine, e.g.
///
/// ```dart
/// class MctsBot
///     extends LocalBot<ObservationData, ActionData, GameConfigData, MctsState>
/// ```
///
/// The infra driver holds bots erased (`List<LocalBot>` on
/// `GameModule`) and serialises the returned action via
/// [BaseEngine.serializeAction], mirroring how it parses observations through the
/// erased engine.
abstract class LocalBot<TObservationData, TActionData, TConfigData, TState> {
  const LocalBot();

  /// Matches a `bots.username` row. The client drives this bot for a seat whose
  /// participant carries this `username` and whose `bots` row has no webhook_url.
  String get username;

  /// Seeds the per-(game, seat) state — the initial "brain" for one seat in one
  /// game (e.g. an empty search tree or a prior belief).
  ///
  /// Runs once on the main isolate when the seat starts being driven, so keep it
  /// light. [engine] is the game's engine, [seatIndex] the bot's seat, and
  /// [config] the bot's `bots.config` row (empty when unset) — for DB-tuned
  /// personas; ignore it if parameterised in the constructor. [TState] is
  /// client-only and never crosses to the server.
  TState createState({
    required BaseEngine<TObservationData, TActionData, TConfigData> engine,
    required int seatIndex,
    required Map<String, dynamic> config,
  });

  /// Returns the bot's move for its seat plus the next state, given the latest
  /// observation and the state from this seat's last *accepted* action.
  ///
  /// **Pure** — see the class doc for the sendability, side-effect, RNG, and
  /// commit-on-accept rules. The action is your game's **typed action** (the same
  /// model your content widget builds for a human tap); infra serialises it
  /// through [BaseEngine.serializeAction], so a human move and a bot move are
  /// interchangeable inputs — never hand-roll the JSON.
  ///
  /// [observation] is the bot seat's parsed observation, [engine] the game's
  /// engine (use it for legality checks / legal-move generation), and
  /// [seatIndex] the bot's seat index.
  FutureOr<({TActionData action, TState state})> chooseAction({
    required BaseEngine<TObservationData, TActionData, TConfigData> engine,
    required TObservationData observation,
    required int seatIndex,
    required TState state,
  });
}
