//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'friend_target.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FriendTarget {
  /// Returns a new [FriendTarget] instance.
  FriendTarget({

    required  this.targetUserId,
  });

  @JsonKey(
    
    name: r'target_user_id',
    required: true,
    includeIfNull: false,
  )


  final String targetUserId;





    @override
    bool operator ==(Object other) => identical(this, other) || other is FriendTarget &&
      other.targetUserId == targetUserId;

    @override
    int get hashCode =>
        targetUserId.hashCode;

  factory FriendTarget.fromJson(Map<String, dynamic> json) => _$FriendTargetFromJson(json);

  Map<String, dynamic> toJson() => _$FriendTargetToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

