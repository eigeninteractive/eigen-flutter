/// Lifecycle status of a game.
///
/// [unknown] is a forward-compatibility sentinel: a status value a newer server
/// sends that this build doesn't recognise decodes to it (via
/// `@JsonKey(unknownEnumValue:)`) instead of throwing. See
/// `docs/backward-compatibility.md`.
enum GameStatus { waiting, ready, active, finished, aborted, unknown }
