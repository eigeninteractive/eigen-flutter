//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/rating_delta_identity_any_of.dart';
import 'package:eigen_api/src/model/rating_delta_identity_any_of1.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rating_delta_identity.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class RatingDeltaIdentity {
  /// Returns a new [RatingDeltaIdentity] instance.
  RatingDeltaIdentity({

    required  this.userId,

    required  this.botId,
  });

  @JsonKey(
    
    name: r'user_id',
    required: true,
    includeIfNull: false,
  )


  final String userId;



  @JsonKey(
    
    name: r'bot_id',
    required: true,
    includeIfNull: false,
  )


  final String botId;





    @override
    bool operator ==(Object other) => identical(this, other) || other is RatingDeltaIdentity &&
      other.userId == userId &&
      other.botId == botId;

    @override
    int get hashCode =>
        userId.hashCode +
        botId.hashCode;

  factory RatingDeltaIdentity.fromJson(Map<String, dynamic> json) => _$RatingDeltaIdentityFromJson(json);

  Map<String, dynamic> toJson() => _$RatingDeltaIdentityToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

