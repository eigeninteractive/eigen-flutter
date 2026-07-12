import 'package:freezed_annotation/freezed_annotation.dart';

part 'replay_frame.freezed.dart';
part 'replay_frame.g.dart';

/// One frame of a finished game's replay — a single entry of the
/// `game/replay` Edge Function response.
///
/// The frames arrive ordered by [version] (version 0 is the initial state, which
/// no action produced). [data] is the caller's observation slice for the frame:
/// their own seat when a participant, or the observer projection when a
/// non-participant replays a public game. It is opaque here — the game's version
/// unit parses it via `GameRules.parseObservation`, exactly like a live frame.
///
/// [pendingPlayers] is that frame's pending set (post-hook narrowing applied);
/// the action fields describe the transition that produced the frame, for
/// rendering move-by-move narration. [actionPlayerIndex] is null for the initial
/// frame and for identity-less system actions (a timeout's affected seats come
/// from the [pendingPlayers] diff against the previous frame, not this field).
@freezed
abstract class ReplayFrame with _$ReplayFrame {
  const factory ReplayFrame({
    required int version,
    required Map<String, dynamic> data,
    required List<int> pendingPlayers,
    required DateTime createdAt,

    /// Who performed the action producing this frame (`user` / `bot` /
    /// `system`); null for the initial frame.
    String? actionType,

    /// Which species produced this frame (`game` or `lifecycle`); null for the
    /// initial frame.
    String? actionKind,

    /// The action payload as logged; null for the initial frame.
    Map<String, dynamic>? actionData,

    /// Performer's seat; null for the initial frame and for system actions.
    int? actionPlayerIndex,
  }) = _ReplayFrame;

  factory ReplayFrame.fromJson(Map<String, dynamic> json) =>
      _$ReplayFrameFromJson(json);
}
