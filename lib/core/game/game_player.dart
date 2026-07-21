import 'package:eigen_api/eigen_api.dart';

/// Unified game-level player concept.
///
/// Composes a seat's game-level data (index, type) with the resolved public
/// identity behind it. The UI layer works exclusively with [GamePlayer], never
/// with the wire [Seat] or [Player] directly: a seat carries only ids, and
/// resolving those to identities is a separate batch lookup.
///
/// Per-game roles (host/guest, team, faction...) are not modelled here - they
/// live in the game's own observation/state JSON, which the game module is
/// free to interpret however it likes.
class GamePlayer {
  const GamePlayer({
    required this.playerIndex,
    required this.type,
    required this.info,
    this.isDeleted = false,
  });

  /// 0-based seat index in the game.
  final int playerIndex;

  /// The type of this participant.
  final SeatTypeEnum type;

  /// Resolved public identity. For a bot seat `info.username` is the bot's
  /// handle, which is also the key its brain is registered under server-side;
  /// bot capability and config come from the cached bot catalog, not here.
  final Player info;

  /// True when the participant's account no longer exists.
  ///
  /// [info] is a synthetic placeholder in this case - its [Player.id] is not a
  /// real id and must not be passed to identity lookups or profile sheets.
  final bool isDeleted;
}
