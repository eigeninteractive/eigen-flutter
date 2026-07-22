//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/rating_identity.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rating_delta.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class RatingDelta {
  /// Returns a new [RatingDelta] instance.
  RatingDelta({
    required this.identity,

    required this.pool,

    required this.muBefore,

    required this.sigmaBefore,

    required this.displayBefore,

    required this.muAfter,

    required this.sigmaAfter,

    required this.displayAfter,

    required this.displayChange,
  });

  @JsonKey(name: r'identity', required: true, includeIfNull: false)
  final RatingIdentity identity;

  @JsonKey(name: r'pool', required: true, includeIfNull: false)
  final String pool;

  @JsonKey(name: r'mu_before', required: true, includeIfNull: false)
  final num muBefore;

  @JsonKey(name: r'sigma_before', required: true, includeIfNull: false)
  final num sigmaBefore;

  @JsonKey(name: r'display_before', required: true, includeIfNull: false)
  final int displayBefore;

  @JsonKey(name: r'mu_after', required: true, includeIfNull: false)
  final num muAfter;

  @JsonKey(name: r'sigma_after', required: true, includeIfNull: false)
  final num sigmaAfter;

  @JsonKey(name: r'display_after', required: true, includeIfNull: false)
  final int displayAfter;

  @JsonKey(name: r'display_change', required: true, includeIfNull: false)
  final int displayChange;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RatingDelta &&
          other.identity == identity &&
          other.pool == pool &&
          other.muBefore == muBefore &&
          other.sigmaBefore == sigmaBefore &&
          other.displayBefore == displayBefore &&
          other.muAfter == muAfter &&
          other.sigmaAfter == sigmaAfter &&
          other.displayAfter == displayAfter &&
          other.displayChange == displayChange;

  @override
  int get hashCode =>
      identity.hashCode +
      pool.hashCode +
      muBefore.hashCode +
      sigmaBefore.hashCode +
      displayBefore.hashCode +
      muAfter.hashCode +
      sigmaAfter.hashCode +
      displayAfter.hashCode +
      displayChange.hashCode;

  factory RatingDelta.fromJson(Map<String, dynamic> json) =>
      _$RatingDeltaFromJson(json);

  Map<String, dynamic> toJson() => _$RatingDeltaToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
