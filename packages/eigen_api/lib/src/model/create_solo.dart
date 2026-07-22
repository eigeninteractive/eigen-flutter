//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'create_solo.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CreateSolo {
  /// Returns a new [CreateSolo] instance.
  CreateSolo({
    required this.schemaVersion,

    required this.config,

    required this.minPlayers,

    required this.maxPlayers,

    this.rated,

    required this.botIds,

    this.turnSeconds,

    this.budgetSeconds,

    this.incrementSeconds,
  });

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

  @JsonKey(name: r'bot_ids', required: true, includeIfNull: false)
  final List<String> botIds;

  @JsonKey(name: r'turn_seconds', required: false, includeIfNull: false)
  final int? turnSeconds;

  @JsonKey(name: r'budget_seconds', required: false, includeIfNull: false)
  final int? budgetSeconds;

  @JsonKey(name: r'increment_seconds', required: false, includeIfNull: false)
  final int? incrementSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreateSolo &&
          other.schemaVersion == schemaVersion &&
          other.config == config &&
          other.minPlayers == minPlayers &&
          other.maxPlayers == maxPlayers &&
          other.rated == rated &&
          other.botIds == botIds &&
          other.turnSeconds == turnSeconds &&
          other.budgetSeconds == budgetSeconds &&
          other.incrementSeconds == incrementSeconds;

  @override
  int get hashCode =>
      schemaVersion.hashCode +
      config.hashCode +
      minPlayers.hashCode +
      maxPlayers.hashCode +
      rated.hashCode +
      botIds.hashCode +
      (turnSeconds == null ? 0 : turnSeconds.hashCode) +
      (budgetSeconds == null ? 0 : budgetSeconds.hashCode) +
      (incrementSeconds == null ? 0 : incrementSeconds.hashCode);

  factory CreateSolo.fromJson(Map<String, dynamic> json) =>
      _$CreateSoloFromJson(json);

  Map<String, dynamic> toJson() => _$CreateSoloToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
