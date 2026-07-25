// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'game_frame_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The [GameRules] version unit for a specific game, resolved once from the
/// game's immutable schema version.
///
/// This is the single version-dispatch point on the client: everything
/// downstream (engine, content, bots, seatability) consumes the resolved unit
/// and never branches on version.

@ProviderFor(gameRules)
final gameRulesProvider = GameRulesFamily._();

/// The [GameRules] version unit for a specific game, resolved once from the
/// game's immutable schema version.
///
/// This is the single version-dispatch point on the client: everything
/// downstream (engine, content, bots, seatability) consumes the resolved unit
/// and never branches on version.

final class GameRulesProvider
    extends
        $FunctionalProvider<
          AsyncValue<GameRules<dynamic, dynamic, dynamic>>,
          GameRules<dynamic, dynamic, dynamic>,
          FutureOr<GameRules<dynamic, dynamic, dynamic>>
        >
    with
        $FutureModifier<GameRules<dynamic, dynamic, dynamic>>,
        $FutureProvider<GameRules<dynamic, dynamic, dynamic>> {
  /// The [GameRules] version unit for a specific game, resolved once from the
  /// game's immutable schema version.
  ///
  /// This is the single version-dispatch point on the client: everything
  /// downstream (engine, content, bots, seatability) consumes the resolved unit
  /// and never branches on version.
  GameRulesProvider._({
    required GameRulesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'gameRulesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$gameRulesHash();

  @override
  String toString() {
    return r'gameRulesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<GameRules<dynamic, dynamic, dynamic>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<GameRules<dynamic, dynamic, dynamic>> create(Ref ref) {
    final argument = this.argument as String;
    return gameRules(ref, gameId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GameRulesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$gameRulesHash() => r'13a2b31e698ff3b5959d5ea0ac8d381f9c86c082';

/// The [GameRules] version unit for a specific game, resolved once from the
/// game's immutable schema version.
///
/// This is the single version-dispatch point on the client: everything
/// downstream (engine, content, bots, seatability) consumes the resolved unit
/// and never branches on version.

final class GameRulesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<GameRules<dynamic, dynamic, dynamic>>,
          String
        > {
  GameRulesFamily._()
    : super(
        retry: null,
        name: r'gameRulesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The [GameRules] version unit for a specific game, resolved once from the
  /// game's immutable schema version.
  ///
  /// This is the single version-dispatch point on the client: everything
  /// downstream (engine, content, bots, seatability) consumes the resolved unit
  /// and never branches on version.

  GameRulesProvider call({required String gameId}) =>
      GameRulesProvider._(argument: gameId, from: this);

  @override
  String toString() => r'gameRulesProvider';
}

/// The parsed game config, produced once from the immutable config payload.
///
/// Config is set at creation and never mutated, so this is long-lived and
/// stands apart from the per-frame [GameFrame]. Erased to [Object] here - the
/// game casts to its concrete type.

@ProviderFor(gameConfig)
final gameConfigProvider = GameConfigFamily._();

/// The parsed game config, produced once from the immutable config payload.
///
/// Config is set at creation and never mutated, so this is long-lived and
/// stands apart from the per-frame [GameFrame]. Erased to [Object] here - the
/// game casts to its concrete type.

final class GameConfigProvider
    extends $FunctionalProvider<AsyncValue<Object>, Object, FutureOr<Object>>
    with $FutureModifier<Object>, $FutureProvider<Object> {
  /// The parsed game config, produced once from the immutable config payload.
  ///
  /// Config is set at creation and never mutated, so this is long-lived and
  /// stands apart from the per-frame [GameFrame]. Erased to [Object] here - the
  /// game casts to its concrete type.
  GameConfigProvider._({
    required GameConfigFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'gameConfigProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$gameConfigHash();

  @override
  String toString() {
    return r'gameConfigProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Object> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Object> create(Ref ref) {
    final argument = this.argument as String;
    return gameConfig(ref, gameId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GameConfigProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$gameConfigHash() => r'0141ca187807433997849c0a3c28be0c5251b3bd';

/// The parsed game config, produced once from the immutable config payload.
///
/// Config is set at creation and never mutated, so this is long-lived and
/// stands apart from the per-frame [GameFrame]. Erased to [Object] here - the
/// game casts to its concrete type.

final class GameConfigFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Object>, String> {
  GameConfigFamily._()
    : super(
        retry: null,
        name: r'gameConfigProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The parsed game config, produced once from the immutable config payload.
  ///
  /// Config is set at creation and never mutated, so this is long-lived and
  /// stands apart from the per-frame [GameFrame]. Erased to [Object] here - the
  /// game casts to its concrete type.

  GameConfigProvider call({required String gameId}) =>
      GameConfigProvider._(argument: gameId, from: this);

  @override
  String toString() => r'gameConfigProvider';
}

/// Memoizes [GameRules.parseObservation] so it only runs when the raw payload
/// changes, not on every rebuild of [gameFrame].

@ProviderFor(_parsedObservation)
final _parsedObservationProvider = _ParsedObservationFamily._();

/// Memoizes [GameRules.parseObservation] so it only runs when the raw payload
/// changes, not on every rebuild of [gameFrame].

final class _ParsedObservationProvider
    extends $FunctionalProvider<Object?, Object?, Object?>
    with $Provider<Object?> {
  /// Memoizes [GameRules.parseObservation] so it only runs when the raw payload
  /// changes, not on every rebuild of [gameFrame].
  _ParsedObservationProvider._({
    required _ParsedObservationFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'_parsedObservationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$_parsedObservationHash();

  @override
  String toString() {
    return r'_parsedObservationProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<Object?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Object? create(Ref ref) {
    final argument = this.argument as String;
    return _parsedObservation(ref, gameId: argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Object? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Object?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _ParsedObservationProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$_parsedObservationHash() =>
    r'6c50ea7926c1598b702d9e9b852ae1325cda4477';

/// Memoizes [GameRules.parseObservation] so it only runs when the raw payload
/// changes, not on every rebuild of [gameFrame].

final class _ParsedObservationFamily extends $Family
    with $FunctionalFamilyOverride<Object?, String> {
  _ParsedObservationFamily._()
    : super(
        retry: null,
        name: r'_parsedObservationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Memoizes [GameRules.parseObservation] so it only runs when the raw payload
  /// changes, not on every rebuild of [gameFrame].

  _ParsedObservationProvider call({required String gameId}) =>
      _ParsedObservationProvider._(argument: gameId, from: this);

  @override
  String toString() => r'_parsedObservationProvider';
}

/// The per-frame [GameFrame] the game renders from.
///
/// Null before the game is under way: frames only exist from v0 of an active
/// game onward, and there is nothing to project in the waiting room or after an
/// abort.
///
/// The parsed config is intentionally not part of this; consume it separately
/// via [gameConfig]. `pendingPlayers`, `version` and `timing` are available as
/// soon as the frame arrives, while `observation` stays null until the rules
/// unit has parsed it.

@ProviderFor(gameFrame)
final gameFrameProvider = GameFrameFamily._();

/// The per-frame [GameFrame] the game renders from.
///
/// Null before the game is under way: frames only exist from v0 of an active
/// game onward, and there is nothing to project in the waiting room or after an
/// abort.
///
/// The parsed config is intentionally not part of this; consume it separately
/// via [gameConfig]. `pendingPlayers`, `version` and `timing` are available as
/// soon as the frame arrives, while `observation` stays null until the rules
/// unit has parsed it.

final class GameFrameProvider
    extends $FunctionalProvider<GameFrame?, GameFrame?, GameFrame?>
    with $Provider<GameFrame?> {
  /// The per-frame [GameFrame] the game renders from.
  ///
  /// Null before the game is under way: frames only exist from v0 of an active
  /// game onward, and there is nothing to project in the waiting room or after an
  /// abort.
  ///
  /// The parsed config is intentionally not part of this; consume it separately
  /// via [gameConfig]. `pendingPlayers`, `version` and `timing` are available as
  /// soon as the frame arrives, while `observation` stays null until the rules
  /// unit has parsed it.
  GameFrameProvider._({
    required GameFrameFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'gameFrameProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$gameFrameHash();

  @override
  String toString() {
    return r'gameFrameProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<GameFrame?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GameFrame? create(Ref ref) {
    final argument = this.argument as String;
    return gameFrame(ref, gameId: argument);
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
    return other is GameFrameProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$gameFrameHash() => r'ab0ae2b9b87118c9d3f2653a1fe2085e683cf5c0';

/// The per-frame [GameFrame] the game renders from.
///
/// Null before the game is under way: frames only exist from v0 of an active
/// game onward, and there is nothing to project in the waiting room or after an
/// abort.
///
/// The parsed config is intentionally not part of this; consume it separately
/// via [gameConfig]. `pendingPlayers`, `version` and `timing` are available as
/// soon as the frame arrives, while `observation` stays null until the rules
/// unit has parsed it.

final class GameFrameFamily extends $Family
    with $FunctionalFamilyOverride<GameFrame?, String> {
  GameFrameFamily._()
    : super(
        retry: null,
        name: r'gameFrameProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The per-frame [GameFrame] the game renders from.
  ///
  /// Null before the game is under way: frames only exist from v0 of an active
  /// game onward, and there is nothing to project in the waiting room or after an
  /// abort.
  ///
  /// The parsed config is intentionally not part of this; consume it separately
  /// via [gameConfig]. `pendingPlayers`, `version` and `timing` are available as
  /// soon as the frame arrives, while `observation` stays null until the rules
  /// unit has parsed it.

  GameFrameProvider call({required String gameId}) =>
      GameFrameProvider._(argument: gameId, from: this);

  @override
  String toString() => r'gameFrameProvider';
}
