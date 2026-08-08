/// Schema version 1 of Rock–Paper–Scissors on the client: the Dart twin of
/// the same-named TypeScript unit in
/// `eigen-server/examples/rps/src/module/v1.ts`.
///
/// The two halves split by authority, not by feature. The TS unit owns
/// everything that decides anything: `initialState`, `applyAction`,
/// `applyLifecycle`, `computeObservation`, and the Zod `schemas`. This unit
/// owns the codec, the legality check that greys out an illegal tap, the
/// optimism contract, and the rendering. Where the two overlap (legality, the
/// two predicates) they are transcriptions, and the shared fixtures under
/// `example/fixtures/v1/` are what keeps them transcriptions.
///
/// A version unit never branches on version. When the rules change
/// incompatibly, copy this file to `v2/`, change it there, and add the entry to
/// [RpsModule.versions]; matches created under v1 keep loading through this
/// unit until they drain.
library;

import 'package:eigen_flutter/eigen_flutter.dart';
import 'package:flutter/widgets.dart';

import 'board.dart';
import 'models.dart';

/// The v1 rules unit, registered under key `1` in [RpsModule.versions].
class RpsRulesV1 extends RpsV1RulesBase {
  const RpsRulesV1();

  /// The legality half of the TS `applyAction`, transcribed.
  ///
  /// Two conditions, and they are the same two the server checks: the seat's
  /// main turn has to be active, and it must not have already thrown this
  /// round. `pending` here is this seat's *masked* projection (see
  /// [previewAction]) so in live play it holds at most your own seat, which
  /// is all this check needs.
  @override
  bool isValidAction({
    required RpsV1Observation obs,
    required List<int> pending,
    required RpsV1Action data,
    required int playerIndex,
    required RpsV1Config config,
  }) => pending.contains(playerIndex) && !obs.committedBy(playerIndex);

  /// Always null. RPS cannot predict its own next observation, and saying so
  /// is the correct answer rather than a gap.
  ///
  /// The reason is the game itself. `computeObservation` masks the opponent's
  /// pending status as well as their commit, so after you throw you genuinely
  /// do not know which of two futures you are in: the opponent has not thrown
  /// yet (your next frame just echoes `yourMove`), or they threw first and
  /// your throw resolves the round (your next frame is a full reveal with a
  /// new score). Predicting either one would be wrong half the time, and a
  /// prediction that is wrong half the time is worse than no prediction: it
  /// shows a reveal that never happened.
  ///
  /// That masking is also what makes simultaneous play work at all: because
  /// the opponent's hidden commit does not change your projected view, the
  /// engine's same-view rule lets both submissions land in either order
  /// without one losing an optimistic-lock race.
  ///
  /// The UI still feels immediate. `board.dart` holds the tapped move in local
  /// widget state and resolves it against the
  /// [GameContentContext.onAction] future. [ActionSubmitResult.committed]
  /// means the very next frame confirms it. That is optimism about *your own
  /// submission*, which you can always know; [previewAction] is optimism about
  /// *the resulting position*, which here you cannot.
  @override
  RpsV1Observation? previewAction({
    required RpsV1Observation obs,
    required List<int> pending,
    required RpsV1Action data,
    required int playerIndex,
    required RpsV1Config config,
  }) => null;

  @override
  Widget buildContent(GameContentContext context) =>
      RpsBoard(context: context, rules: this);

  /// Display-only twin of the TS `ratingPool`. The server recomputes it at
  /// creation, so a wrong answer here only mis-renders the Rated toggle.
  @override
  String? ratingPool(RatingPoolArgs args) =>
      args.access == GameAccess.public ? 'standard' : null;

  /// RPS asks nothing of a bot, so every registered bot can take a seat.
  @override
  bool botSeatable(BotSeatableArgs args) => true;
}
