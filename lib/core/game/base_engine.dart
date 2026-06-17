/// Base class that all game implementations must extend.
///
/// Intentionally minimal. Game-over and winner are *not* concerns of this
/// class — those are infra-level facts surfaced via `games.status` and
/// `game_outcomes`. Player counts live on [GameCreationSpec] and player
/// identities arrive via `PlayersContext` — the engine's only job is local
/// action-legality validation plus pure rendering helpers.
///
/// Type parameters:
/// - [TObservationData]: The game-specific observation payload (JSONB-backed).
/// - [TActionData]: The game-specific action payload (JSONB-backed).
/// - [TConfigData]: The per-instance config payload (JSONB-backed).
abstract class BaseEngine<TObservationData, TActionData, TConfigData> {
  BaseEngine(this.config, {required this.schemaVersion});

  /// Configuration for this game instance.
  final TConfigData config;

  /// The game-type schema version this game was created under
  /// (`games.schema_version`).
  ///
  /// Branch on this in [parseObservation] (and rendering) when the observation
  /// shape changes across versions, so a game started under an older schema
  /// keeps parsing correctly.
  final int schemaVersion;

  /// Parses a raw observation JSON map into the game-specific type.
  ///
  /// Called once per network event in the session provider — never on
  /// frame rebuild. Implement by delegating to the Freezed `fromJson`:
  /// ```dart
  /// @override
  /// ObservationData parseObservation(Map<String, dynamic> json) =>
  ///     ObservationData.fromJson(json);
  /// ```
  TObservationData parseObservation(Map<String, dynamic> json);

  /// Validates local legality of an action for client-side UX feedback.
  ///
  /// The authoritative check runs server-side in `game_apply_action`; this is
  /// for disabling illegal taps and similar. All four parameters are passed
  /// to every game so the contract stays uniform across turn styles; simple
  /// games can ignore whatever they don't need.
  ///
  /// Parameters:
  /// - [obs]: the current typed game payload (board, hand, fog, ...).
  /// - [pendingPlayers]: 0-based indices whose "main turn" is active right
  ///   now. Mirror of `game_states.pending_players`. Games with interrupt
  ///   actions (e.g. Exploding Kittens's Nope) use this to distinguish a
  ///   main-turn action (only pending players may play) from an interrupt
  ///   (anyone holding the card may play).
  /// - [action]: the candidate action payload.
  /// - [playerIndex]: the 0-based index of the player attempting [action].
  ///   For games where piece ownership matters (Chess — only your color;
  ///   Exploding Kittens — only cards in your hand), this identifies the
  ///   actor. Sequential games that don't care about ownership (TicTacToe)
  ///   can ignore it.
  bool isValidAction(
    TObservationData obs,
    List<int> pendingPlayers,
    TActionData action,
    int playerIndex,
  );
}
