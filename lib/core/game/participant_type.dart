/// The type of a participant in a game.
///
/// [unknown] is a forward-compatibility sentinel for values a newer server may
/// introduce. See `docs/backward-compatibility.md`.
enum ParticipantType { human, bot, unknown }
