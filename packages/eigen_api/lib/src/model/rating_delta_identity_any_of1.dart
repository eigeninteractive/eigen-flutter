//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rating_delta_identity_any_of1.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class RatingDeltaIdentityAnyOf1 {
  /// Returns a new [RatingDeltaIdentityAnyOf1] instance.
  RatingDeltaIdentityAnyOf1({

    required  this.botId,
  });

  @JsonKey(
    
    name: r'bot_id',
    required: true,
    includeIfNull: false,
  )


  final String botId;





    @override
    bool operator ==(Object other) => identical(this, other) || other is RatingDeltaIdentityAnyOf1 &&
      other.botId == botId;

    @override
    int get hashCode =>
        botId.hashCode;

  factory RatingDeltaIdentityAnyOf1.fromJson(Map<String, dynamic> json) => _$RatingDeltaIdentityAnyOf1FromJson(json);

  Map<String, dynamic> toJson() => _$RatingDeltaIdentityAnyOf1ToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

