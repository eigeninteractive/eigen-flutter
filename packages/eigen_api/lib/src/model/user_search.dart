//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/player.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'user_search.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class UserSearch {
  /// Returns a new [UserSearch] instance.
  UserSearch({

    required  this.users,
  });

  @JsonKey(
    
    name: r'users',
    required: true,
    includeIfNull: false,
  )


  final List<Player> users;





    @override
    bool operator ==(Object other) => identical(this, other) || other is UserSearch &&
      other.users == users;

    @override
    int get hashCode =>
        users.hashCode;

  factory UserSearch.fromJson(Map<String, dynamic> json) => _$UserSearchFromJson(json);

  Map<String, dynamic> toJson() => _$UserSearchToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

