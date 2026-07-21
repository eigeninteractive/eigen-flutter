//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'device_registration.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DeviceRegistration {
  /// Returns a new [DeviceRegistration] instance.
  DeviceRegistration({

    required  this.fid,

    required  this.platform,
  });

  @JsonKey(
    
    name: r'fid',
    required: true,
    includeIfNull: false,
  )


  final String fid;



  @JsonKey(
    
    name: r'platform',
    required: true,
    includeIfNull: false,
  )


  final DeviceRegistrationPlatformEnum platform;





    @override
    bool operator ==(Object other) => identical(this, other) || other is DeviceRegistration &&
      other.fid == fid &&
      other.platform == platform;

    @override
    int get hashCode =>
        fid.hashCode +
        platform.hashCode;

  factory DeviceRegistration.fromJson(Map<String, dynamic> json) => _$DeviceRegistrationFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceRegistrationToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum DeviceRegistrationPlatformEnum {
@JsonValue(r'ios')
ios(r'ios'),
@JsonValue(r'android')
android(r'android'),
@JsonValue(r'web')
web(r'web');

const DeviceRegistrationPlatformEnum(this.value);

final String value;

@override
String toString() => value;
}


