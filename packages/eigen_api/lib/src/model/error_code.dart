//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

/// A stable machine code identifying why a request failed.
enum ErrorCode {
  /// A stable machine code identifying why a request failed.
  @JsonValue(r'not_active')
  notActive(r'not_active'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'not_ready')
  notReady(r'not_ready'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'expired')
  expired(r'expired'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'not_pending')
  notPending(r'not_pending'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'state_updated')
  stateUpdated(r'state_updated'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'invalid_payload')
  invalidPayload(r'invalid_payload'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'illegal_move')
  illegalMove(r'illegal_move'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'unknown_game')
  unknownGame(r'unknown_game'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'not_joinable')
  notJoinable(r'not_joinable'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'game_full')
  gameFull(r'game_full'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'already_joined')
  alreadyJoined(r'already_joined'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'not_participant')
  notParticipant(r'not_participant'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'not_creator')
  notCreator(r'not_creator'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'creator_cannot_leave')
  creatorCannotLeave(r'creator_cannot_leave'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'schema_unsupported')
  schemaUnsupported(r'schema_unsupported'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'username_invalid')
  usernameInvalid(r'username_invalid'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'username_taken')
  usernameTaken(r'username_taken'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'friends_only')
  friendsOnly(r'friends_only'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'registration_required')
  registrationRequired(r'registration_required'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'image_too_large')
  imageTooLarge(r'image_too_large'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'unsupported_image_type')
  unsupportedImageType(r'unsupported_image_type'),

  /// A stable machine code identifying why a request failed.
  @JsonValue(r'rate_limited')
  rateLimited(r'rate_limited');

  const ErrorCode(this.value);

  final String value;

  @override
  String toString() => value;
}
