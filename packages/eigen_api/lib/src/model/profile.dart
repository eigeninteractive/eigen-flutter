//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'profile.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Profile {
  /// Returns a new [Profile] instance.
  Profile({

    required  this.id,

    required  this.username,

    required  this.displayName,

    required  this.avatarUrl,

    required  this.isAnonymous,

    required  this.email,

    required  this.createdAt,
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
    includeIfNull: false,
  )


  final String avatarUrl;



  @JsonKey(
    
    name: r'is_anonymous',
    required: true,
    includeIfNull: false,
  )


  final bool isAnonymous;



  @JsonKey(
    
    name: r'email',
    required: true,
    includeIfNull: true,
  )


  final String? email;



  @JsonKey(
    
    name: r'created_at',
    required: true,
    includeIfNull: false,
  )


  final num createdAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Profile &&
      other.id == id &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl &&
      other.isAnonymous == isAnonymous &&
      other.email == email &&
      other.createdAt == createdAt;

    @override
    int get hashCode =>
        id.hashCode +
        username.hashCode +
        displayName.hashCode +
        avatarUrl.hashCode +
        isAnonymous.hashCode +
        (email == null ? 0 : email.hashCode) +
        createdAt.hashCode;

  factory Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

