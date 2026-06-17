import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:eigen_engine/core/game/game_status.dart';

part 'game.freezed.dart';
part 'game.g.dart';

/// Access level for a game.
///
/// [unknown] is a forward-compatibility sentinel for values a newer server may
/// introduce.
enum GameAccess { public, private, friends, unknown }

/// Game metadata from the games table.
///
/// Does not contain game_state (which is in a separate service-role table).
/// Clients see game state through observations.
@freezed
abstract class Game with _$Game {
  const factory Game({
    required String id,
    String? createdBy,
    @JsonKey(unknownEnumValue: GameStatus.unknown) required GameStatus status,
    @JsonKey(unknownEnumValue: GameAccess.unknown) required GameAccess access,

    /// Seconds per turn (per-action timer). Null means untimed or budget mode.
    int? turnSeconds,

    /// Personal time budget per player in seconds. Null means no bank.
    int? budgetSeconds,

    /// Seconds added to the acting player's bank after each budget-consuming
    /// action (Fischer increment). Null treated as zero.
    int? incrementSeconds,

    /// Minimum players required to transition the game to 'ready' status.
    required int minPlayers,

    /// Maximum players allowed to join.
    required int maxPlayers,
    required Map<String, dynamic> config,

    /// Game-type schema version this game was created under
    /// (`games.schema_version`, a `NOT NULL` column the server always
    /// provides).
    required int schemaVersion,
    String? shortCode,

    /// Whether this game counts toward player skill ratings.
    required bool rated,

    /// Rating pool name (e.g. 'rapid', 'daily'). Non-null iff [rated] is true.
    String? ratingPool,

    required DateTime createdAt,
    DateTime? finishedAt,
    required DateTime updatedAt,
  }) = _Game;

  factory Game.fromJson(Map<String, dynamic> json) => _$GameFromJson(json);
}
