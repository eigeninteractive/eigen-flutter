import 'dart:async';

import 'package:eigen_engine/core/game/base_engine.dart';

/// A local bot: computes a legal move for a bot seat, client-side.
///
/// Game-specific logic, so implementations live in the game package (alongside
/// the `GameModule`), not the engine — the engine owns only this contract and
/// the wiring. A local bot is only ever driven in a *solo* game (one human +
/// bot(s)); the engine enforces that and reveals a bot seat's observation to the
/// human's client only when no other human is present.
///
/// **Implementations must be stateless.** Entries in `GameModule.localBots` are
/// `const` and a single instance is reused across every call — across turns,
/// across the several seats one identity may hold, and across games. Derive
/// everything from the [chooseAction] arguments; never cache per-game or per-seat
/// state on the instance, or it will bleed between seats and games. Constructor
/// fields are fine as long as they are immutable configuration (e.g. a search
/// depth).
///
/// Generic over the same `<TObservationData, TActionData, TConfigData>` triple as
/// [BaseEngine], so a bot is fully typed against its game's engine — declare it
/// exactly like the engine, e.g.
/// `class MinimaxBot extends LocalBot<ObservationData, ActionData, GameConfigData>`.
/// The infra driver holds bots erased (`List<LocalBot>` on `GameModule`) and
/// serialises the returned action via [BaseEngine.serializeAction], mirroring how
/// it parses observations through the erased engine.
abstract class LocalBot<TObservationData, TActionData, TConfigData> {
  const LocalBot();

  /// Matches a `bots.username` row. The client drives this bot for a seat whose
  /// participant carries this `username` and whose `bots` row has no webhook_url.
  String get username;

  /// Returns the bot's move for its seat, given the seat's parsed observation.
  ///
  /// Returns your game's **typed action** — the same model your content widget
  /// builds for a human tap. Infra serialises it through
  /// [BaseEngine.serializeAction] into the JSON `data` the `game_apply_action`
  /// hook consumes, so a human move and a bot move are interchangeable inputs.
  /// Routing both producers through the one engine seam is what keeps them
  /// uniform; never hand-roll the JSON.
  ///
  /// [observation] is the bot seat's parsed observation (the same typed value
  /// `BaseEngine.parseObservation` yields). [engine] is the game's engine — use
  /// it for legality checks / legal-move generation. [botSeatIndex] is the bot's
  /// seat index.
  ///
  /// [config] is the bot's operator-defined `bots.config` (empty when unset). It
  /// lets one implementation back many named personas (N:1) tuned from the DB
  /// row; bots parameterized purely in their constructor can ignore it.
  FutureOr<TActionData> chooseAction({
    required BaseEngine<TObservationData, TActionData, TConfigData> engine,
    required TObservationData observation,
    required int botSeatIndex,
    required Map<String, dynamic> config,
  });
}
