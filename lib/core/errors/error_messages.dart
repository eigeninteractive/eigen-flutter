import 'package:dio/dio.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/errors/engine_exception.dart';

/// Converts a raw exception into a message suitable for display in a snackbar
/// or inline form error.
///
/// Copy is chosen by the server's stable [ErrorCode], never by matching message
/// text, so rewording a server message can never change what the user sees.
/// Uncoded failures get the generic message rather than the server's own text —
/// those are validation details and unexpected 500s, whose wording is
/// diagnostic and sometimes internal.
String humanize(Object e) => switch (e) {
  EngineException(:final code?) => messageForCode(code),
  // The server answered, but with nothing the UI can specialise on.
  EngineException() => _unexpected,
  // No response at all: engineCall only converts failures that carried one, so
  // any DioException reaching here is a genuine transport failure.
  DioException() => _offline,
  _ => _unexpected,
};

/// Display copy for every code the server can send.
///
/// Exhaustive over [ErrorCode] with no fallback arm, so adding a code
/// server-side fails to compile here until copy is written for it. That is the
/// point: a silent generic message for a code we have specific advice for is a
/// UX regression that is otherwise invisible.
String messageForCode(ErrorCode code) => switch (code) {
  // Kernel rejections — the move reached the game and it refused.
  ErrorCode.notActive => 'This game has already ended.',
  ErrorCode.notReady => 'This game needs more players before it can start.',
  ErrorCode.expired => 'Time ran out for this turn.',
  ErrorCode.notPending => "It's not your turn.",
  ErrorCode.stateUpdated => 'The game updated — try again.',
  ErrorCode.invalidPayload => "That move isn't valid.",
  ErrorCode.illegalMove => "That move isn't allowed.",
  // Lobby rejections.
  ErrorCode.unknownGame => 'Game not found. Check the code and try again.',
  ErrorCode.notJoinable => 'This game has already started.',
  ErrorCode.gameFull => 'This game is already full.',
  ErrorCode.alreadyJoined => "You're already in this game.",
  ErrorCode.notParticipant => "You're not in this game.",
  ErrorCode.notCreator => 'Only the host can do that.',
  ErrorCode.creatorCannotLeave =>
    'You created this game — cancel it instead of leaving.',
  // Raised before the command reached the game.
  ErrorCode.schemaUnsupported => 'Update your app to play this game.',
  ErrorCode.usernameInvalid =>
    'Usernames are 3–20 characters: lowercase letters, digits, dots, or '
        'underscores.',
  ErrorCode.usernameTaken => 'That username is already taken.',
  ErrorCode.friendsOnly => 'Only friends of the host can join this game.',
  ErrorCode.registrationRequired => 'Create an account to do that.',
  ErrorCode.imageTooLarge => 'That image is too large. Try a smaller one.',
  ErrorCode.unsupportedImageType => 'Use a JPEG, PNG, or WebP image.',
};

const _offline = "Can't reach the server. Check your connection.";
const _unexpected = 'Something went wrong. Please try again.';
