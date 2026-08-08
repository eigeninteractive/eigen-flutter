// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'replay_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The full ordered frame history of a finished game, fetched once.
///
/// A finished game's history is immutable, so this is fetched a single time and
/// cached for the life of the replay screen. A participant receives their own
/// seat's projection; a non-participant replaying a public game receives the
/// observer projection - the shape is identical either way, so the replay UI
/// does not branch on it.
///
/// The same range endpoint backs live gap recovery; replay is just the whole
/// range rather than a missing slice of it.

@ProviderFor(replayFrames)
final replayFramesProvider = ReplayFramesFamily._();

/// The full ordered frame history of a finished game, fetched once.
///
/// A finished game's history is immutable, so this is fetched a single time and
/// cached for the life of the replay screen. A participant receives their own
/// seat's projection; a non-participant replaying a public game receives the
/// observer projection - the shape is identical either way, so the replay UI
/// does not branch on it.
///
/// The same range endpoint backs live gap recovery; replay is just the whole
/// range rather than a missing slice of it.

final class ReplayFramesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Frame>>,
          List<Frame>,
          FutureOr<List<Frame>>
        >
    with $FutureModifier<List<Frame>>, $FutureProvider<List<Frame>> {
  /// The full ordered frame history of a finished game, fetched once.
  ///
  /// A finished game's history is immutable, so this is fetched a single time and
  /// cached for the life of the replay screen. A participant receives their own
  /// seat's projection; a non-participant replaying a public game receives the
  /// observer projection - the shape is identical either way, so the replay UI
  /// does not branch on it.
  ///
  /// The same range endpoint backs live gap recovery; replay is just the whole
  /// range rather than a missing slice of it.
  ReplayFramesProvider._({
    required ReplayFramesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'replayFramesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$replayFramesHash();

  @override
  String toString() {
    return r'replayFramesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Frame>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Frame>> create(Ref ref) {
    final argument = this.argument as String;
    return replayFrames(ref, gameId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReplayFramesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$replayFramesHash() => r'78a7fc0c0751437ef4af6f8e1d1f53b9adc0da2f';

/// The full ordered frame history of a finished game, fetched once.
///
/// A finished game's history is immutable, so this is fetched a single time and
/// cached for the life of the replay screen. A participant receives their own
/// seat's projection; a non-participant replaying a public game receives the
/// observer projection - the shape is identical either way, so the replay UI
/// does not branch on it.
///
/// The same range endpoint backs live gap recovery; replay is just the whole
/// range rather than a missing slice of it.

final class ReplayFramesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Frame>>, String> {
  ReplayFramesFamily._()
    : super(
        retry: null,
        name: r'replayFramesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The full ordered frame history of a finished game, fetched once.
  ///
  /// A finished game's history is immutable, so this is fetched a single time and
  /// cached for the life of the replay screen. A participant receives their own
  /// seat's projection; a non-participant replaying a public game receives the
  /// observer projection - the shape is identical either way, so the replay UI
  /// does not branch on it.
  ///
  /// The same range endpoint backs live gap recovery; replay is just the whole
  /// range rather than a missing slice of it.

  ReplayFramesProvider call({required String gameId}) =>
      ReplayFramesProvider._(argument: gameId, from: this);

  @override
  String toString() => r'replayFramesProvider';
}

/// The current position within a game's replay, as an index into
/// [replayFramesProvider].
///
/// Starts at 0 (the initial frame) so the replay plays forward from the
/// beginning. [frameCount] is passed by the screen once the frames have
/// loaded, so stepping and scrubbing clamp to the valid range without the
/// controller re-reading the async list. Stepping forward one frame keeps the
/// underlying `version` consecutive, which is what lets the game animate the
/// transition; jumping or stepping back is non-consecutive and snaps.

@ProviderFor(ReplayCursor)
final replayCursorProvider = ReplayCursorFamily._();

/// The current position within a game's replay, as an index into
/// [replayFramesProvider].
///
/// Starts at 0 (the initial frame) so the replay plays forward from the
/// beginning. [frameCount] is passed by the screen once the frames have
/// loaded, so stepping and scrubbing clamp to the valid range without the
/// controller re-reading the async list. Stepping forward one frame keeps the
/// underlying `version` consecutive, which is what lets the game animate the
/// transition; jumping or stepping back is non-consecutive and snaps.
final class ReplayCursorProvider extends $NotifierProvider<ReplayCursor, int> {
  /// The current position within a game's replay, as an index into
  /// [replayFramesProvider].
  ///
  /// Starts at 0 (the initial frame) so the replay plays forward from the
  /// beginning. [frameCount] is passed by the screen once the frames have
  /// loaded, so stepping and scrubbing clamp to the valid range without the
  /// controller re-reading the async list. Stepping forward one frame keeps the
  /// underlying `version` consecutive, which is what lets the game animate the
  /// transition; jumping or stepping back is non-consecutive and snaps.
  ReplayCursorProvider._({
    required ReplayCursorFamily super.from,
    required ({String gameId, int frameCount}) super.argument,
  }) : super(
         retry: null,
         name: r'replayCursorProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$replayCursorHash();

  @override
  String toString() {
    return r'replayCursorProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ReplayCursor create() => ReplayCursor();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReplayCursorProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$replayCursorHash() => r'412dea05055bd4d31859fc511c4b094a61079609';

/// The current position within a game's replay, as an index into
/// [replayFramesProvider].
///
/// Starts at 0 (the initial frame) so the replay plays forward from the
/// beginning. [frameCount] is passed by the screen once the frames have
/// loaded, so stepping and scrubbing clamp to the valid range without the
/// controller re-reading the async list. Stepping forward one frame keeps the
/// underlying `version` consecutive, which is what lets the game animate the
/// transition; jumping or stepping back is non-consecutive and snaps.

final class ReplayCursorFamily extends $Family
    with
        $ClassFamilyOverride<
          ReplayCursor,
          int,
          int,
          int,
          ({String gameId, int frameCount})
        > {
  ReplayCursorFamily._()
    : super(
        retry: null,
        name: r'replayCursorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The current position within a game's replay, as an index into
  /// [replayFramesProvider].
  ///
  /// Starts at 0 (the initial frame) so the replay plays forward from the
  /// beginning. [frameCount] is passed by the screen once the frames have
  /// loaded, so stepping and scrubbing clamp to the valid range without the
  /// controller re-reading the async list. Stepping forward one frame keeps the
  /// underlying `version` consecutive, which is what lets the game animate the
  /// transition; jumping or stepping back is non-consecutive and snaps.

  ReplayCursorProvider call({
    required String gameId,
    required int frameCount,
  }) => ReplayCursorProvider._(
    argument: (gameId: gameId, frameCount: frameCount),
    from: this,
  );

  @override
  String toString() => r'replayCursorProvider';
}

/// The current position within a game's replay, as an index into
/// [replayFramesProvider].
///
/// Starts at 0 (the initial frame) so the replay plays forward from the
/// beginning. [frameCount] is passed by the screen once the frames have
/// loaded, so stepping and scrubbing clamp to the valid range without the
/// controller re-reading the async list. Stepping forward one frame keeps the
/// underlying `version` consecutive, which is what lets the game animate the
/// transition; jumping or stepping back is non-consecutive and snaps.

abstract class _$ReplayCursor extends $Notifier<int> {
  late final _$args = ref.$arg as ({String gameId, int frameCount});
  String get gameId => _$args.gameId;
  int get frameCount => _$args.frameCount;

  int build({required String gameId, required int frameCount});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(gameId: _$args.gameId, frameCount: _$args.frameCount),
    );
  }
}

/// The [GameFrame] for a single replay frame index.
///
/// Memoized per `(gameId, index)`: [GameRules.parseObservation] runs once per
/// frame no matter how often the user steps back and forth across it. Timing is
/// always empty, since a replay has no live clocks. Returns null until the frames
/// and the version unit have both loaded, or for an out-of-range index.

@ProviderFor(replayFrameAt)
final replayFrameAtProvider = ReplayFrameAtFamily._();

/// The [GameFrame] for a single replay frame index.
///
/// Memoized per `(gameId, index)`: [GameRules.parseObservation] runs once per
/// frame no matter how often the user steps back and forth across it. Timing is
/// always empty, since a replay has no live clocks. Returns null until the frames
/// and the version unit have both loaded, or for an out-of-range index.

final class ReplayFrameAtProvider
    extends $FunctionalProvider<GameFrame?, GameFrame?, GameFrame?>
    with $Provider<GameFrame?> {
  /// The [GameFrame] for a single replay frame index.
  ///
  /// Memoized per `(gameId, index)`: [GameRules.parseObservation] runs once per
  /// frame no matter how often the user steps back and forth across it. Timing is
  /// always empty, since a replay has no live clocks. Returns null until the frames
  /// and the version unit have both loaded, or for an out-of-range index.
  ReplayFrameAtProvider._({
    required ReplayFrameAtFamily super.from,
    required ({String gameId, int index}) super.argument,
  }) : super(
         retry: null,
         name: r'replayFrameAtProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$replayFrameAtHash();

  @override
  String toString() {
    return r'replayFrameAtProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<GameFrame?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GameFrame? create(Ref ref) {
    final argument = this.argument as ({String gameId, int index});
    return replayFrameAt(ref, gameId: argument.gameId, index: argument.index);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GameFrame? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GameFrame?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReplayFrameAtProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$replayFrameAtHash() => r'2db71a9d8886942ff93570311cd6c915991702d0';

/// The [GameFrame] for a single replay frame index.
///
/// Memoized per `(gameId, index)`: [GameRules.parseObservation] runs once per
/// frame no matter how often the user steps back and forth across it. Timing is
/// always empty, since a replay has no live clocks. Returns null until the frames
/// and the version unit have both loaded, or for an out-of-range index.

final class ReplayFrameAtFamily extends $Family
    with $FunctionalFamilyOverride<GameFrame?, ({String gameId, int index})> {
  ReplayFrameAtFamily._()
    : super(
        retry: null,
        name: r'replayFrameAtProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The [GameFrame] for a single replay frame index.
  ///
  /// Memoized per `(gameId, index)`: [GameRules.parseObservation] runs once per
  /// frame no matter how often the user steps back and forth across it. Timing is
  /// always empty, since a replay has no live clocks. Returns null until the frames
  /// and the version unit have both loaded, or for an out-of-range index.

  ReplayFrameAtProvider call({required String gameId, required int index}) =>
      ReplayFrameAtProvider._(
        argument: (gameId: gameId, index: index),
        from: this,
      );

  @override
  String toString() => r'replayFrameAtProvider';
}
