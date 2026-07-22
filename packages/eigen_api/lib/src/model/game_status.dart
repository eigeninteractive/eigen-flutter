//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

enum GameStatus {
  @JsonValue(r'waiting')
  waiting(r'waiting'),
  @JsonValue(r'ready')
  ready(r'ready'),
  @JsonValue(r'active')
  active(r'active'),
  @JsonValue(r'finished')
  finished(r'finished'),
  @JsonValue(r'aborted')
  aborted(r'aborted');

  const GameStatus(this.value);

  final String value;

  @override
  String toString() => value;
}
