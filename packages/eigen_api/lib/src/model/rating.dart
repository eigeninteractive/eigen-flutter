//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rating.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Rating {
  /// Returns a new [Rating] instance.
  Rating({

    required  this.pool,

    required  this.mu,

    required  this.sigma,

    required  this.displayRating,

    required  this.updatedAt,
  });

  @JsonKey(
    
    name: r'pool',
    required: true,
    includeIfNull: false,
  )


  final String pool;



  @JsonKey(
    
    name: r'mu',
    required: true,
    includeIfNull: false,
  )


  final num mu;



  @JsonKey(
    
    name: r'sigma',
    required: true,
    includeIfNull: false,
  )


  final num sigma;



  @JsonKey(
    
    name: r'display_rating',
    required: true,
    includeIfNull: false,
  )


  final int displayRating;



  @JsonKey(
    
    name: r'updated_at',
    required: true,
    includeIfNull: false,
  )


  final int updatedAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Rating &&
      other.pool == pool &&
      other.mu == mu &&
      other.sigma == sigma &&
      other.displayRating == displayRating &&
      other.updatedAt == updatedAt;

    @override
    int get hashCode =>
        pool.hashCode +
        mu.hashCode +
        sigma.hashCode +
        displayRating.hashCode +
        updatedAt.hashCode;

  factory Rating.fromJson(Map<String, dynamic> json) => _$RatingFromJson(json);

  Map<String, dynamic> toJson() => _$RatingToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

