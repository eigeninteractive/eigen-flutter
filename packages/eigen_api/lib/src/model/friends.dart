//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/friend.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'friends.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Friends {
  /// Returns a new [Friends] instance.
  Friends({

    required  this.friends,
  });

  @JsonKey(
    
    name: r'friends',
    required: true,
    includeIfNull: false,
  )


  final List<Friend> friends;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Friends &&
      other.friends == friends;

    @override
    int get hashCode =>
        friends.hashCode;

  factory Friends.fromJson(Map<String, dynamic> json) => _$FriendsFromJson(json);

  Map<String, dynamic> toJson() => _$FriendsToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

