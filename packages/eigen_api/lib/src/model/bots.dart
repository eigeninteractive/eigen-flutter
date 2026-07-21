//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/bot.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'bots.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Bots {
  /// Returns a new [Bots] instance.
  Bots({

    required  this.bots,
  });

  @JsonKey(
    
    name: r'bots',
    required: true,
    includeIfNull: false,
  )


  final List<Bot> bots;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Bots &&
      other.bots == bots;

    @override
    int get hashCode =>
        bots.hashCode;

  factory Bots.fromJson(Map<String, dynamic> json) => _$BotsFromJson(json);

  Map<String, dynamic> toJson() => _$BotsToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

