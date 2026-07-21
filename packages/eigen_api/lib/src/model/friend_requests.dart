//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/friend_request.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'friend_requests.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FriendRequests {
  /// Returns a new [FriendRequests] instance.
  FriendRequests({

    required  this.requests,
  });

  @JsonKey(
    
    name: r'requests',
    required: true,
    includeIfNull: false,
  )


  final List<FriendRequest> requests;





    @override
    bool operator ==(Object other) => identical(this, other) || other is FriendRequests &&
      other.requests == requests;

    @override
    int get hashCode =>
        requests.hashCode;

  factory FriendRequests.fromJson(Map<String, dynamic> json) => _$FriendRequestsFromJson(json);

  Map<String, dynamic> toJson() => _$FriendRequestsToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

