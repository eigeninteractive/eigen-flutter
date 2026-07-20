import 'package:eigen_flutter/shared/data/models/player_info.dart';
import 'package:eigen_flutter/core/game/participant_type.dart';

/// Unified game-level player concept.
///
/// Composes a participant's game-level data (seat, type) with their resolved
/// public identity ([PlayerInfo]). The UI layer works exclusively with
/// [GamePlayer] — never touching [Participant] directly.
///
/// [Participant] remains the data-layer model for DB row parsing;
/// [GamePlayer] is the consumption-layer model for rendering.
///
/// Per-game roles (host/guest, team, faction…) are not modelled here — they
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
  final ParticipantType type;

  /// Resolved public identity (username, avatar, rating, etc.). For a bot seat
  /// `info.username` is the bot's handle (`bots.username`) — the local-bot driver
  /// matches it against [GameRules.localBots]; bot capability/config comes from
  /// the cached bot catalog, not from here.
  final PlayerInfo info;

  /// True when the participant's account no longer exists.
  ///
  /// [info] is a synthetic placeholder in this case — its [PlayerInfo.id] is
  /// not a real database UUID and must not be passed to identity lookups or
  /// profile sheets.
  final bool isDeleted;
}
