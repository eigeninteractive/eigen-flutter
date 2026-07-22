//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/game_access.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'create_game.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CreateGame {
  /// Returns a new [CreateGame] instance.
  CreateGame({
    required this.access,

    required this.schemaVersion,

    required this.config,

    required this.minPlayers,

    required this.maxPlayers,

    this.rated,

    this.turnSeconds,

    this.budgetSeconds,

    this.incrementSeconds,
  });

  @JsonKey(name: r'access', required: true, includeIfNull: false)
  final GameAccess access;

  @JsonKey(name: r'schema_version', required: true, includeIfNull: false)
  final int schemaVersion;

  @JsonKey(name: r'config', required: true, includeIfNull: false)
  final Object config;

  // minimum: 1
  @JsonKey(name: r'min_players', required: true, includeIfNull: false)
  final int minPlayers;

  // minimum: 1
  @JsonKey(name: r'max_players', required: true, includeIfNull: false)
  final int maxPlayers;

  @JsonKey(name: r'rated', required: false, includeIfNull: false)
  final bool? rated;

  @JsonKey(name: r'turn_seconds', required: false, includeIfNull: false)
  final int? turnSeconds;

  @JsonKey(name: r'budget_seconds', required: false, includeIfNull: false)
  final int? budgetSeconds;

  @JsonKey(name: r'increment_seconds', required: false, includeIfNull: false)
  final int? incrementSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreateGame &&
          other.access == access &&
          other.schemaVersion == schemaVersion &&
          other.config == config &&
          other.minPlayers == minPlayers &&
          other.maxPlayers == maxPlayers &&
          other.rated == rated &&
          other.turnSeconds == turnSeconds &&
          other.budgetSeconds == budgetSeconds &&
          other.incrementSeconds == incrementSeconds;

  @override
  int get hashCode =>
      access.hashCode +
      schemaVersion.hashCode +
      config.hashCode +
      minPlayers.hashCode +
      maxPlayers.hashCode +
      rated.hashCode +
      (turnSeconds == null ? 0 : turnSeconds.hashCode) +
      (budgetSeconds == null ? 0 : budgetSeconds.hashCode) +
      (incrementSeconds == null ? 0 : incrementSeconds.hashCode);

  factory CreateGame.fromJson(Map<String, dynamic> json) =>
      _$CreateGameFromJson(json);

  Map<String, dynamic> toJson() => _$CreateGameToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
