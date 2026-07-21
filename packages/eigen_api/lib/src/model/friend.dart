//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'friend.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Friend {
  /// Returns a new [Friend] instance.
  Friend({

    required  this.username,

    required  this.displayName,

    required  this.avatarUrl,

    required  this.isAnonymous,

    required  this.userId,

    required  this.since,
  });

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
    
    name: r'is_anonymous',
    required: true,
    includeIfNull: false,
  )


  final bool isAnonymous;



  @JsonKey(
    
    name: r'user_id',
    required: true,
    includeIfNull: false,
  )


  final String userId;



  @JsonKey(
    
    name: r'since',
    required: true,
    includeIfNull: false,
  )


  final int since;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Friend &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl &&
      other.isAnonymous == isAnonymous &&
      other.userId == userId &&
      other.since == since;

    @override
    int get hashCode =>
        username.hashCode +
        displayName.hashCode +
        (avatarUrl == null ? 0 : avatarUrl.hashCode) +
        isAnonymous.hashCode +
        userId.hashCode +
        since.hashCode;

  factory Friend.fromJson(Map<String, dynamic> json) => _$FriendFromJson(json);

  Map<String, dynamic> toJson() => _$FriendToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

