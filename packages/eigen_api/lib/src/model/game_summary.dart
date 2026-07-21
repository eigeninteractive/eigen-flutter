//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/seat.dart';
import 'package:eigen_api/src/model/game_status.dart';
import 'package:eigen_api/src/model/game_access.dart';
import 'package:eigen_api/src/model/outcome.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'game_summary.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GameSummary {
  /// Returns a new [GameSummary] instance.
  GameSummary({

    required  this.id,

    required  this.createdBy,

    required  this.status,

    required  this.access,

    required  this.schemaVersion,

    required  this.config,

    required  this.turnSeconds,

    required  this.budgetSeconds,

    required  this.incrementSeconds,

    required  this.rated,

    required  this.ratingPool,

    required  this.minPlayers,

    required  this.maxPlayers,

    required  this.shortCode,

    required  this.pendingPlayers,

    required  this.turnDeadline,

    required  this.outcomes,

    required  this.finishedAt,

    required  this.createdAt,

    required  this.updatedAt,

    required  this.participants,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final String id;



  @JsonKey(
    
    name: r'created_by',
    required: true,
    includeIfNull: true,
  )


  final String? createdBy;



  @JsonKey(
    
    name: r'status',
    required: true,
    includeIfNull: false,
  )


  final GameStatus status;



  @JsonKey(
    
    name: r'access',
    required: true,
    includeIfNull: false,
  )


  final GameAccess access;



  @JsonKey(
    
    name: r'schema_version',
    required: true,
    includeIfNull: false,
  )


  final int schemaVersion;



  @JsonKey(
    
    name: r'config',
    required: true,
    includeIfNull: false,
  )


  final Object config;



  @JsonKey(
    
    name: r'turn_seconds',
    required: true,
    includeIfNull: true,
  )


  final num? turnSeconds;



  @JsonKey(
    
    name: r'budget_seconds',
    required: true,
    includeIfNull: true,
  )


  final num? budgetSeconds;



  @JsonKey(
    
    name: r'increment_seconds',
    required: true,
    includeIfNull: true,
  )


  final num? incrementSeconds;



  @JsonKey(
    
    name: r'rated',
    required: true,
    includeIfNull: false,
  )


  final bool rated;



  @JsonKey(
    
    name: r'rating_pool',
    required: true,
    includeIfNull: true,
  )


  final String? ratingPool;



  @JsonKey(
    
    name: r'min_players',
    required: true,
    includeIfNull: false,
  )


  final int minPlayers;



  @JsonKey(
    
    name: r'max_players',
    required: true,
    includeIfNull: false,
  )


  final int maxPlayers;



  @JsonKey(
    
    name: r'short_code',
    required: true,
    includeIfNull: false,
  )


  final String shortCode;



  @JsonKey(
    
    name: r'pending_players',
    required: true,
    includeIfNull: true,
  )


  final List<int>? pendingPlayers;



  @JsonKey(
    
    name: r'turn_deadline',
    required: true,
    includeIfNull: true,
  )


  final num? turnDeadline;



  @JsonKey(
    
    name: r'outcomes',
    required: true,
    includeIfNull: true,
  )


  final List<Outcome>? outcomes;



  @JsonKey(
    
    name: r'finished_at',
    required: true,
    includeIfNull: true,
  )


  final num? finishedAt;



  @JsonKey(
    
    name: r'created_at',
    required: true,
    includeIfNull: false,
  )


  final num createdAt;



  @JsonKey(
    
    name: r'updated_at',
    required: true,
    includeIfNull: false,
  )


  final num updatedAt;



  @JsonKey(
    
    name: r'participants',
    required: true,
    includeIfNull: false,
  )


  final List<Seat> participants;





    @override
    bool operator ==(Object other) => identical(this, other) || other is GameSummary &&
      other.id == id &&
      other.createdBy == createdBy &&
      other.status == status &&
      other.access == access &&
      other.schemaVersion == schemaVersion &&
      other.config == config &&
      other.turnSeconds == turnSeconds &&
      other.budgetSeconds == budgetSeconds &&
      other.incrementSeconds == incrementSeconds &&
      other.rated == rated &&
      other.ratingPool == ratingPool &&
      other.minPlayers == minPlayers &&
      other.maxPlayers == maxPlayers &&
      other.shortCode == shortCode &&
      other.pendingPlayers == pendingPlayers &&
      other.turnDeadline == turnDeadline &&
      other.outcomes == outcomes &&
      other.finishedAt == finishedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.participants == participants;

    @override
    int get hashCode =>
        id.hashCode +
        (createdBy == null ? 0 : createdBy.hashCode) +
        status.hashCode +
        access.hashCode +
        schemaVersion.hashCode +
        config.hashCode +
        (turnSeconds == null ? 0 : turnSeconds.hashCode) +
        (budgetSeconds == null ? 0 : budgetSeconds.hashCode) +
        (incrementSeconds == null ? 0 : incrementSeconds.hashCode) +
        rated.hashCode +
        (ratingPool == null ? 0 : ratingPool.hashCode) +
        minPlayers.hashCode +
        maxPlayers.hashCode +
        shortCode.hashCode +
        (pendingPlayers == null ? 0 : pendingPlayers.hashCode) +
        (turnDeadline == null ? 0 : turnDeadline.hashCode) +
        (outcomes == null ? 0 : outcomes.hashCode) +
        (finishedAt == null ? 0 : finishedAt.hashCode) +
        createdAt.hashCode +
        updatedAt.hashCode +
        participants.hashCode;

  factory GameSummary.fromJson(Map<String, dynamic> json) => _$GameSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$GameSummaryToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

