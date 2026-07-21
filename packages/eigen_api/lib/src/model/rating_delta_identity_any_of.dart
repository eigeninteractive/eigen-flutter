//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rating_delta_identity_any_of.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class RatingDeltaIdentityAnyOf {
  /// Returns a new [RatingDeltaIdentityAnyOf] instance.
  RatingDeltaIdentityAnyOf({

    required  this.userId,
  });

  @JsonKey(
    
    name: r'user_id',
    required: true,
    includeIfNull: false,
  )


  final String userId;





    @override
    bool operator ==(Object other) => identical(this, other) || other is RatingDeltaIdentityAnyOf &&
      other.userId == userId;

    @override
    int get hashCode =>
        userId.hashCode;

  factory RatingDeltaIdentityAnyOf.fromJson(Map<String, dynamic> json) => _$RatingDeltaIdentityAnyOfFromJson(json);

  Map<String, dynamic> toJson() => _$RatingDeltaIdentityAnyOfToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

