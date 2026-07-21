//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'bot.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Bot {
  /// Returns a new [Bot] instance.
  Bot({

    required  this.id,

    required  this.username,

    required  this.displayName,

    required  this.avatarUrl,

    required  this.schemaVersion,

    required  this.ratedEligible,

    required  this.config,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final String id;



  @JsonKey(
    
    name: r'username',
    required: true,
    includeIfNull: false,
  )


  final String username;



  @JsonKey(
    
    name: r'display_name',
    required: true,
    includeIfNull: false,
  )


  final String displayName;



  @JsonKey(
    
    name: r'avatar_url',
    required: true,
    includeIfNull: true,
  )


  final String? avatarUrl;



  @JsonKey(
    
    name: r'schema_version',
    required: true,
    includeIfNull: false,
  )


  final int schemaVersion;



  @JsonKey(
    
    name: r'rated_eligible',
    required: true,
    includeIfNull: false,
  )


  final bool ratedEligible;



  @JsonKey(
    
    name: r'config',
    required: true,
    includeIfNull: false,
  )


  final Object config;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Bot &&
      other.id == id &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl &&
      other.schemaVersion == schemaVersion &&
      other.ratedEligible == ratedEligible &&
      other.config == config;

    @override
    int get hashCode =>
        id.hashCode +
        username.hashCode +
        displayName.hashCode +
        (avatarUrl == null ? 0 : avatarUrl.hashCode) +
        schemaVersion.hashCode +
        ratedEligible.hashCode +
        config.hashCode;

  factory Bot.fromJson(Map<String, dynamic> json) => _$BotFromJson(json);

  Map<String, dynamic> toJson() => _$BotToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

