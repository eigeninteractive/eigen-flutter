//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'username_update.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class UsernameUpdate {
  /// Returns a new [UsernameUpdate] instance.
  UsernameUpdate({

    required  this.username,
  });

  @JsonKey(
    
    name: r'username',
    required: true,
    includeIfNull: false,
  )


  final String username;





    @override
    bool operator ==(Object other) => identical(this, other) || other is UsernameUpdate &&
      other.username == username;

    @override
    int get hashCode =>
        username.hashCode;

  factory UsernameUpdate.fromJson(Map<String, dynamic> json) => _$UsernameUpdateFromJson(json);

  Map<String, dynamic> toJson() => _$UsernameUpdateToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

