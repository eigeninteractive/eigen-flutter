/// A structured error from the engine backend — an edge-function route or a
/// SQL RPC.
///
/// Thrown by the repository layer whenever the server itself responded with
/// an error (as opposed to a transport failure, which surfaces as the
/// underlying network exception). [code] carries the engine's stable error
/// code when the failure has one; dispatch on it, never on [message] — the
/// message is display copy and may be reworded.
class EngineException implements Exception {
  const EngineException(this.message, {this.code});

  /// The server's human-readable error text (used as fallback display copy).
  final String message;

  /// The stable engine error code (see [EngineErrorCodes]), or null when the
  /// failure carried none (request validation, unexpected 500s).
  final String? code;

  @override
  String toString() => message;
}

/// The engine's stable error codes — the Dart twin of the TS `EngineCode`
/// registry (`_engine/runtime.ts`) and the SQL `EIGxx` SQLSTATEs. Keep the
/// three in sync.
///
/// The codes surface on [EngineException.code] for both transports: the
/// repository layer maps edge-function error bodies and client-direct `app_*`
/// RPC failures (via `dbGuard`) to [EngineException].
abstract final class EngineErrorCodes {
  /// A rated finish raced a concurrent rating update (server-side retryable;
  /// reaching the client means retries were exhausted).
  static const ratingConflict = 'EIG01';

  /// The board advanced past the version the action was computed against.
  static const staleVersion = 'EIG02';

  /// The turn deadline (plus grace) had already passed.
  static const turnExpired = 'EIG03';

  /// The acting seat is not in the pending set.
  static const notYourTurn = 'EIG04';

  /// The game is no longer active.
  static const gameNotActive = 'EIG05';

  /// No game with that id or code.
  static const gameNotFound = 'EIG06';

  /// The caller holds no seat in this game.
  static const notParticipant = 'EIG07';

  /// The game already has its maximum number of players.
  static const gameFull = 'EIG08';

  /// The caller already holds a seat in this game.
  static const alreadyJoined = 'EIG09';

  /// The game has already started (or ended) and cannot be joined.
  static const notAcceptingPlayers = 'EIG10';

  /// A friends-access game and the caller is not a friend of the creator.
  static const friendsOnly = 'EIG11';

  /// The game's schema version is not supported by this build.
  static const unsupportedSchema = 'EIG12';

  /// The submitted username fails the format rules.
  static const usernameInvalid = 'EIG13';

  /// The submitted username is already taken.
  static const usernameTaken = 'EIG14';

  /// The caller is not authenticated.
  static const notAuthenticated = 'EIG15';

  /// The game's `applyAction` rejected the move as illegal.
  static const illegalMove = 'EIG16';
}
