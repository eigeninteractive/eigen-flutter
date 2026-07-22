//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:eigen_api/src/model/frame.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'frames.g.dart';

@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Frames {
  /// Returns a new [Frames] instance.
  Frames({required this.frames});

  @JsonKey(name: r'frames', required: true, includeIfNull: false)
  final List<Frame> frames;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Frames && other.frames == frames;

  @override
  int get hashCode => frames.hashCode;

  factory Frames.fromJson(Map<String, dynamic> json) => _$FramesFromJson(json);

  Map<String, dynamic> toJson() => _$FramesToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
