//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

enum GameAccess {
  @JsonValue(r'public')
  public(r'public'),
  @JsonValue(r'private')
  private(r'private'),
  @JsonValue(r'friends')
  friends(r'friends');

  const GameAccess(this.value);

  final String value;

  @override
  String toString() => value;
}
