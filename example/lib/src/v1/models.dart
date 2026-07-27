/// Handwritten game behavior layered over the generated v1 payload types.
///
/// Regenerate [payloads.dart] from the Worker-owned game contract; keep
/// methods and display behavior here so generation can replace the payload
/// file wholesale.
library;

import 'payloads.dart';

export 'payloads.dart'
    show
        RpsV1Action,
        RpsV1Config,
        RpsV1Move,
        RpsV1Observation,
        RpsV1RulesBase,
        RpsV1Round;

extension RpsV1MoveRules on RpsV1Move {
  /// Whether this throw beats [other]. Display-only: the server owns scoring.
  bool beats(RpsV1Move other) => switch (this) {
    RpsV1Move.rock => other == RpsV1Move.scissors,
    RpsV1Move.paper => other == RpsV1Move.rock,
    RpsV1Move.scissors => other == RpsV1Move.paper,
  };
}

extension RpsV1ObservationRules on RpsV1Observation {
  /// Whether [seat] has committed under the live or replay projection.
  bool committedBy(int seat) =>
      commits != null ? commits![seat] != null : yourMove != null;
}
