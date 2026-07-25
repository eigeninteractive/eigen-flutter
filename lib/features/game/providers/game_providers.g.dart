// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'game_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for GameRepository instance.

@ProviderFor(gameRepository)
final gameRepositoryProvider = GameRepositoryProvider._();

/// Provider for GameRepository instance.

final class GameRepositoryProvider
    extends $FunctionalProvider<GameRepository, GameRepository, GameRepository>
    with $Provider<GameRepository> {
  /// Provider for GameRepository instance.
  GameRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gameRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gameRepositoryHash();

  @$internal
  @override
  $ProviderElement<GameRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GameRepository create(Ref ref) {
    return gameRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GameRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GameRepository>(value),
    );
  }
}

String _$gameRepositoryHash() => r'876f2c91a563f9542ed11e76beff4c65cf491fd7';

/// The active [GameModule].
///
/// Override in [ProviderScope] via:
/// ```dart
/// currentGameModuleProvider.overrideWithValue(const TicTacToeModule())
/// ```
/// Throws [UnimplementedError] at startup if no override is provided.

@ProviderFor(currentGameModule)
final currentGameModuleProvider = CurrentGameModuleProvider._();

/// The active [GameModule].
///
/// Override in [ProviderScope] via:
/// ```dart
/// currentGameModuleProvider.overrideWithValue(const TicTacToeModule())
/// ```
/// Throws [UnimplementedError] at startup if no override is provided.

final class CurrentGameModuleProvider
    extends $FunctionalProvider<GameModule, GameModule, GameModule>
    with $Provider<GameModule> {
  /// The active [GameModule].
  ///
  /// Override in [ProviderScope] via:
  /// ```dart
  /// currentGameModuleProvider.overrideWithValue(const TicTacToeModule())
  /// ```
  /// Throws [UnimplementedError] at startup if no override is provided.
  CurrentGameModuleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentGameModuleProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentGameModuleHash();

  @$internal
  @override
  $ProviderElement<GameModule> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GameModule create(Ref ref) {
    return currentGameModule(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GameModule value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GameModule>(value),
    );
  }
}

String _$currentGameModuleHash() => r'261bd79bd7189c66d74b3bb73e5877a5c1db946b';

/// The bot catalog for this deployment - the pickers' source of truth.
///
/// `keepAlive`: static reference data that changes rarely (bots are registered
/// by an operator), so it is fetched once and reused for the session.
///
/// `@JsonPersist()` caches it to SQLite so the pickers resolve from cache
/// (~5 ms) on cold start, before the network refresh lands. The catalog is
/// deployment-global public reference data - like [PlayerInfoCache] it is not
/// user-scoped and not cleared on sign-out, so the auto-derived global storage
/// key is correct.

@ProviderFor(AvailableBots)
@JsonPersist()
final availableBotsProvider = AvailableBotsProvider._();

/// The bot catalog for this deployment - the pickers' source of truth.
///
/// `keepAlive`: static reference data that changes rarely (bots are registered
/// by an operator), so it is fetched once and reused for the session.
///
/// `@JsonPersist()` caches it to SQLite so the pickers resolve from cache
/// (~5 ms) on cold start, before the network refresh lands. The catalog is
/// deployment-global public reference data - like [PlayerInfoCache] it is not
/// user-scoped and not cleared on sign-out, so the auto-derived global storage
/// key is correct.
@JsonPersist()
final class AvailableBotsProvider
    extends $AsyncNotifierProvider<AvailableBots, List<Bot>> {
  /// The bot catalog for this deployment - the pickers' source of truth.
  ///
  /// `keepAlive`: static reference data that changes rarely (bots are registered
  /// by an operator), so it is fetched once and reused for the session.
  ///
  /// `@JsonPersist()` caches it to SQLite so the pickers resolve from cache
  /// (~5 ms) on cold start, before the network refresh lands. The catalog is
  /// deployment-global public reference data - like [PlayerInfoCache] it is not
  /// user-scoped and not cleared on sign-out, so the auto-derived global storage
  /// key is correct.
  AvailableBotsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableBotsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableBotsHash();

  @$internal
  @override
  AvailableBots create() => AvailableBots();
}

String _$availableBotsHash() => r'8110c1a9b87cbbe07dae8ee2e1a8ec33a67783e9';

/// The bot catalog for this deployment - the pickers' source of truth.
///
/// `keepAlive`: static reference data that changes rarely (bots are registered
/// by an operator), so it is fetched once and reused for the session.
///
/// `@JsonPersist()` caches it to SQLite so the pickers resolve from cache
/// (~5 ms) on cold start, before the network refresh lands. The catalog is
/// deployment-global public reference data - like [PlayerInfoCache] it is not
/// user-scoped and not cleared on sign-out, so the auto-derived global storage
/// key is correct.

@JsonPersist()
abstract class _$AvailableBotsBase extends $AsyncNotifier<List<Bot>> {
  FutureOr<List<Bot>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Bot>>, List<Bot>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Bot>>, List<Bot>>,
              AsyncValue<List<Bot>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The bot catalog indexed by id, for O(1) capability lookups.

@ProviderFor(botCatalogById)
final botCatalogByIdProvider = BotCatalogByIdProvider._();

/// The bot catalog indexed by id, for O(1) capability lookups.

final class BotCatalogByIdProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, Bot>>,
          Map<String, Bot>,
          FutureOr<Map<String, Bot>>
        >
    with $FutureModifier<Map<String, Bot>>, $FutureProvider<Map<String, Bot>> {
  /// The bot catalog indexed by id, for O(1) capability lookups.
  BotCatalogByIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'botCatalogByIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$botCatalogByIdHash();

  @$internal
  @override
  $FutureProviderElement<Map<String, Bot>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, Bot>> create(Ref ref) {
    return botCatalogById(ref);
  }
}

String _$botCatalogByIdHash() => r'2b2144eb85fffe5224794b1078a7d6e8476cd860';

/// Whether the solo-play entry should be offered for this deployment.
///
/// Two conditions, both enforced server-side too - this only avoids offering an
/// entry that would fail:
///
/// 1. **A bot this build's rules can play.** Solo creation always targets the
///    latest version, so usability is judged against the latest unit.
/// 2. **A timed mode.** A *server-seated* bot requires one: dispatch is
///    single-attempt, so if a bot's turn is never delivered the only thing that
///    resolves the game is the turn deadline firing the server's alarm. Untimed
///    means no deadline, no alarm, and a game wedged forever - the server
///    refuses it on the seating path.
///
/// Guests are deliberately *not* gated out: solo-vs-bot is a guest's first-run
/// experience, and the server accepts it - the game simply comes out unrated,
/// since rating requires a registered account.
///
/// Gating on both - rather than just "a bot exists" - keeps an untimed-only
/// deployment from showing a solo entry that opens a dead-end picker.
///
/// The timing condition is deliberately tied to *server* seating rather than to
/// bots in general, because the deferred offline-solo path will not share it: a
/// client-driven bot has no dispatch to fail, so an on-device game can be
/// untimed. When that lands, this becomes a choice between two solo modes
/// (untimed on-device, timed server-seated) rather than a single gate, and the
/// partition it needs is already the one expressed here.

@ProviderFor(soloPlayAvailable)
final soloPlayAvailableProvider = SoloPlayAvailableProvider._();

/// Whether the solo-play entry should be offered for this deployment.
///
/// Two conditions, both enforced server-side too - this only avoids offering an
/// entry that would fail:
///
/// 1. **A bot this build's rules can play.** Solo creation always targets the
///    latest version, so usability is judged against the latest unit.
/// 2. **A timed mode.** A *server-seated* bot requires one: dispatch is
///    single-attempt, so if a bot's turn is never delivered the only thing that
///    resolves the game is the turn deadline firing the server's alarm. Untimed
///    means no deadline, no alarm, and a game wedged forever - the server
///    refuses it on the seating path.
///
/// Guests are deliberately *not* gated out: solo-vs-bot is a guest's first-run
/// experience, and the server accepts it - the game simply comes out unrated,
/// since rating requires a registered account.
///
/// Gating on both - rather than just "a bot exists" - keeps an untimed-only
/// deployment from showing a solo entry that opens a dead-end picker.
///
/// The timing condition is deliberately tied to *server* seating rather than to
/// bots in general, because the deferred offline-solo path will not share it: a
/// client-driven bot has no dispatch to fail, so an on-device game can be
/// untimed. When that lands, this becomes a choice between two solo modes
/// (untimed on-device, timed server-seated) rather than a single gate, and the
/// partition it needs is already the one expressed here.

final class SoloPlayAvailableProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the solo-play entry should be offered for this deployment.
  ///
  /// Two conditions, both enforced server-side too - this only avoids offering an
  /// entry that would fail:
  ///
  /// 1. **A bot this build's rules can play.** Solo creation always targets the
  ///    latest version, so usability is judged against the latest unit.
  /// 2. **A timed mode.** A *server-seated* bot requires one: dispatch is
  ///    single-attempt, so if a bot's turn is never delivered the only thing that
  ///    resolves the game is the turn deadline firing the server's alarm. Untimed
  ///    means no deadline, no alarm, and a game wedged forever - the server
  ///    refuses it on the seating path.
  ///
  /// Guests are deliberately *not* gated out: solo-vs-bot is a guest's first-run
  /// experience, and the server accepts it - the game simply comes out unrated,
  /// since rating requires a registered account.
  ///
  /// Gating on both - rather than just "a bot exists" - keeps an untimed-only
  /// deployment from showing a solo entry that opens a dead-end picker.
  ///
  /// The timing condition is deliberately tied to *server* seating rather than to
  /// bots in general, because the deferred offline-solo path will not share it: a
  /// client-driven bot has no dispatch to fail, so an on-device game can be
  /// untimed. When that lands, this becomes a choice between two solo modes
  /// (untimed on-device, timed server-seated) rather than a single gate, and the
  /// partition it needs is already the one expressed here.
  SoloPlayAvailableProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'soloPlayAvailableProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$soloPlayAvailableHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return soloPlayAvailable(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$soloPlayAvailableHash() => r'7b8d7806324db9dbdeedb2d26f22f47a47139eef';

/// The caller's games, "your turn" first then most recently updated.
///
/// One request: the summary already carries the roster, the pending set and
/// the deadline, so nothing has to be derived from a second read.

@ProviderFor(activeGames)
final activeGamesProvider = ActiveGamesProvider._();

/// The caller's games, "your turn" first then most recently updated.
///
/// One request: the summary already carries the roster, the pending set and
/// the deadline, so nothing has to be derived from a second read.

final class ActiveGamesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<GameSummary>>,
          List<GameSummary>,
          FutureOr<List<GameSummary>>
        >
    with
        $FutureModifier<List<GameSummary>>,
        $FutureProvider<List<GameSummary>> {
  /// The caller's games, "your turn" first then most recently updated.
  ///
  /// One request: the summary already carries the roster, the pending set and
  /// the deadline, so nothing has to be derived from a second read.
  ActiveGamesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeGamesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeGamesHash();

  @$internal
  @override
  $FutureProviderElement<List<GameSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<GameSummary>> create(Ref ref) {
    return activeGames(ref);
  }
}

String _$activeGamesHash() => r'3d2e1b090ecec8292f8d2329cbeb8899ac6b843d';

/// One game's metadata: schema version, config, timing, access.
///
/// A plain read rather than a stream. These fields are fixed at creation and
/// never change, so streaming them would be re-delivering constants; what does
/// change - status and roster - arrives on [gameEvents] instead.

@ProviderFor(gameSummary)
final gameSummaryProvider = GameSummaryFamily._();

/// One game's metadata: schema version, config, timing, access.
///
/// A plain read rather than a stream. These fields are fixed at creation and
/// never change, so streaming them would be re-delivering constants; what does
/// change - status and roster - arrives on [gameEvents] instead.

final class GameSummaryProvider
    extends
        $FunctionalProvider<
          AsyncValue<GameSummary>,
          GameSummary,
          FutureOr<GameSummary>
        >
    with $FutureModifier<GameSummary>, $FutureProvider<GameSummary> {
  /// One game's metadata: schema version, config, timing, access.
  ///
  /// A plain read rather than a stream. These fields are fixed at creation and
  /// never change, so streaming them would be re-delivering constants; what does
  /// change - status and roster - arrives on [gameEvents] instead.
  GameSummaryProvider._({
    required GameSummaryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'gameSummaryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$gameSummaryHash();

  @override
  String toString() {
    return r'gameSummaryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<GameSummary> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<GameSummary> create(Ref ref) {
    final argument = this.argument as String;
    return gameSummary(ref, gameId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GameSummaryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$gameSummaryHash() => r'ce8af36d61093b519a70ab8ffdfb8fec4410178b';

/// One game's metadata: schema version, config, timing, access.
///
/// A plain read rather than a stream. These fields are fixed at creation and
/// never change, so streaming them would be re-delivering constants; what does
/// change - status and roster - arrives on [gameEvents] instead.

final class GameSummaryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<GameSummary>, String> {
  GameSummaryFamily._()
    : super(
        retry: null,
        name: r'gameSummaryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One game's metadata: schema version, config, timing, access.
  ///
  /// A plain read rather than a stream. These fields are fixed at creation and
  /// never change, so streaming them would be re-delivering constants; what does
  /// change - status and roster - arrives on [gameEvents] instead.

  GameSummaryProvider call({required String gameId}) =>
      GameSummaryProvider._(argument: gameId, from: this);

  @override
  String toString() => r'gameSummaryProvider';
}

/// The game's live feed: roster snapshots pre-game, then ordered frames.
///
/// One socket serves the whole game, so this is the single subscription a game
/// screen needs. Riverpod's automatic retry covers a failure to establish it;
/// drops after that are handled inside the socket, which reconnects and
/// resyncs without tearing down this stream.

@ProviderFor(gameEvents)
final gameEventsProvider = GameEventsFamily._();

/// The game's live feed: roster snapshots pre-game, then ordered frames.
///
/// One socket serves the whole game, so this is the single subscription a game
/// screen needs. Riverpod's automatic retry covers a failure to establish it;
/// drops after that are handled inside the socket, which reconnects and
/// resyncs without tearing down this stream.

final class GameEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<GameSocketEvent>,
          GameSocketEvent,
          Stream<GameSocketEvent>
        >
    with $FutureModifier<GameSocketEvent>, $StreamProvider<GameSocketEvent> {
  /// The game's live feed: roster snapshots pre-game, then ordered frames.
  ///
  /// One socket serves the whole game, so this is the single subscription a game
  /// screen needs. Riverpod's automatic retry covers a failure to establish it;
  /// drops after that are handled inside the socket, which reconnects and
  /// resyncs without tearing down this stream.
  GameEventsProvider._({
    required GameEventsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'gameEventsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$gameEventsHash();

  @override
  String toString() {
    return r'gameEventsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<GameSocketEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<GameSocketEvent> create(Ref ref) {
    final argument = this.argument as String;
    return gameEvents(ref, gameId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GameEventsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$gameEventsHash() => r'7ab8245a9b0ae956a12f6641a4fcb02c4dc94069';

/// The game's live feed: roster snapshots pre-game, then ordered frames.
///
/// One socket serves the whole game, so this is the single subscription a game
/// screen needs. Riverpod's automatic retry covers a failure to establish it;
/// drops after that are handled inside the socket, which reconnects and
/// resyncs without tearing down this stream.

final class GameEventsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<GameSocketEvent>, String> {
  GameEventsFamily._()
    : super(
        retry: null,
        name: r'gameEventsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The game's live feed: roster snapshots pre-game, then ordered frames.
  ///
  /// One socket serves the whole game, so this is the single subscription a game
  /// screen needs. Riverpod's automatic retry covers a failure to establish it;
  /// drops after that are handled inside the socket, which reconnects and
  /// resyncs without tearing down this stream.

  GameEventsProvider call({required String gameId}) =>
      GameEventsProvider._(argument: gameId, from: this);

  @override
  String toString() => r'gameEventsProvider';
}

/// The newest roster seen for a game, seeded from the summary.
///
/// The socket delivers a snapshot on open and on every roster change while the
/// game is in the waiting room, but sends none once play starts - so the
/// summary provides the starting value and later snapshots replace it.

@ProviderFor(gameRoster)
final gameRosterProvider = GameRosterFamily._();

/// The newest roster seen for a game, seeded from the summary.
///
/// The socket delivers a snapshot on open and on every roster change while the
/// game is in the waiting room, but sends none once play starts - so the
/// summary provides the starting value and later snapshots replace it.

final class GameRosterProvider
    extends $FunctionalProvider<AsyncValue<Roster>, Roster, FutureOr<Roster>>
    with $FutureModifier<Roster>, $FutureProvider<Roster> {
  /// The newest roster seen for a game, seeded from the summary.
  ///
  /// The socket delivers a snapshot on open and on every roster change while the
  /// game is in the waiting room, but sends none once play starts - so the
  /// summary provides the starting value and later snapshots replace it.
  GameRosterProvider._({
    required GameRosterFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'gameRosterProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$gameRosterHash();

  @override
  String toString() {
    return r'gameRosterProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Roster> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Roster> create(Ref ref) {
    final argument = this.argument as String;
    return gameRoster(ref, gameId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GameRosterProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$gameRosterHash() => r'e1999de717570cb2f0fc784c3152b8d5e8a74954';

/// The newest roster seen for a game, seeded from the summary.
///
/// The socket delivers a snapshot on open and on every roster change while the
/// game is in the waiting room, but sends none once play starts - so the
/// summary provides the starting value and later snapshots replace it.

final class GameRosterFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Roster>, String> {
  GameRosterFamily._()
    : super(
        retry: null,
        name: r'gameRosterProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The newest roster seen for a game, seeded from the summary.
  ///
  /// The socket delivers a snapshot on open and on every roster change while the
  /// game is in the waiting room, but sends none once play starts - so the
  /// summary provides the starting value and later snapshots replace it.

  GameRosterProvider call({required String gameId}) =>
      GameRosterProvider._(argument: gameId, from: this);

  @override
  String toString() => r'gameRosterProvider';
}

/// The newest frame seen for a game, or null before the first one arrives.

@ProviderFor(gameFrameData)
final gameFrameDataProvider = GameFrameDataFamily._();

/// The newest frame seen for a game, or null before the first one arrives.

final class GameFrameDataProvider
    extends $FunctionalProvider<Frame?, Frame?, Frame?>
    with $Provider<Frame?> {
  /// The newest frame seen for a game, or null before the first one arrives.
  GameFrameDataProvider._({
    required GameFrameDataFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'gameFrameDataProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$gameFrameDataHash();

  @override
  String toString() {
    return r'gameFrameDataProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<Frame?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Frame? create(Ref ref) {
    final argument = this.argument as String;
    return gameFrameData(ref, gameId: argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Frame? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Frame?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GameFrameDataProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$gameFrameDataHash() => r'0f72c283d3bef104c0f793c72789b7cf40c040f7';

/// The newest frame seen for a game, or null before the first one arrives.

final class GameFrameDataFamily extends $Family
    with $FunctionalFamilyOverride<Frame?, String> {
  GameFrameDataFamily._()
    : super(
        retry: null,
        name: r'gameFrameDataProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The newest frame seen for a game, or null before the first one arrives.

  GameFrameDataProvider call({required String gameId}) =>
      GameFrameDataProvider._(argument: gameId, from: this);

  @override
  String toString() => r'gameFrameDataProvider';
}

/// The game's seats with their identities resolved, plus which one is mine.
///
/// Seats come from the live roster rather than a separate fetch, so this
/// re-derives as players join and leave. Identities come from the persisted
/// player cache, which covers humans and bots alike.

@ProviderFor(gamePlayers)
final gamePlayersProvider = GamePlayersFamily._();

/// The game's seats with their identities resolved, plus which one is mine.
///
/// Seats come from the live roster rather than a separate fetch, so this
/// re-derives as players join and leave. Identities come from the persisted
/// player cache, which covers humans and bots alike.

final class GamePlayersProvider
    extends
        $FunctionalProvider<
          AsyncValue<PlayersContext>,
          PlayersContext,
          FutureOr<PlayersContext>
        >
    with $FutureModifier<PlayersContext>, $FutureProvider<PlayersContext> {
  /// The game's seats with their identities resolved, plus which one is mine.
  ///
  /// Seats come from the live roster rather than a separate fetch, so this
  /// re-derives as players join and leave. Identities come from the persisted
  /// player cache, which covers humans and bots alike.
  GamePlayersProvider._({
    required GamePlayersFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'gamePlayersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$gamePlayersHash();

  @override
  String toString() {
    return r'gamePlayersProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<PlayersContext> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PlayersContext> create(Ref ref) {
    final argument = this.argument as String;
    return gamePlayers(ref, gameId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GamePlayersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$gamePlayersHash() => r'c872020092eec0c5abd91a05e7b249eb2304b8e2';

/// The game's seats with their identities resolved, plus which one is mine.
///
/// Seats come from the live roster rather than a separate fetch, so this
/// re-derives as players join and leave. Identities come from the persisted
/// player cache, which covers humans and bots alike.

final class GamePlayersFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<PlayersContext>, String> {
  GamePlayersFamily._()
    : super(
        retry: null,
        name: r'gamePlayersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The game's seats with their identities resolved, plus which one is mine.
  ///
  /// Seats come from the live roster rather than a separate fetch, so this
  /// re-derives as players join and leave. Identities come from the persisted
  /// player cache, which covers humans and bots alike.

  GamePlayersProvider call({required String gameId}) =>
      GamePlayersProvider._(argument: gameId, from: this);

  @override
  String toString() => r'gamePlayersProvider';
}

/// Joins a game by invite code, returning the game's id and its roster.
///
/// Auto-disposes once the join screen navigates away. The screen uses
/// [ref.listen] to react to the result rather than watching the value
/// directly, so navigation happens exactly once.

@ProviderFor(joinByCode)
final joinByCodeProvider = JoinByCodeFamily._();

/// Joins a game by invite code, returning the game's id and its roster.
///
/// Auto-disposes once the join screen navigates away. The screen uses
/// [ref.listen] to react to the result rather than watching the value
/// directly, so navigation happens exactly once.

final class JoinByCodeProvider
    extends $FunctionalProvider<AsyncValue<Joined>, Joined, FutureOr<Joined>>
    with $FutureModifier<Joined>, $FutureProvider<Joined> {
  /// Joins a game by invite code, returning the game's id and its roster.
  ///
  /// Auto-disposes once the join screen navigates away. The screen uses
  /// [ref.listen] to react to the result rather than watching the value
  /// directly, so navigation happens exactly once.
  JoinByCodeProvider._({
    required JoinByCodeFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'joinByCodeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$joinByCodeHash();

  @override
  String toString() {
    return r'joinByCodeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Joined> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Joined> create(Ref ref) {
    final argument = this.argument as String;
    return joinByCode(ref, code: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is JoinByCodeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$joinByCodeHash() => r'9363d23309783281be2e4aadf28d50dcf5640d7e';

/// Joins a game by invite code, returning the game's id and its roster.
///
/// Auto-disposes once the join screen navigates away. The screen uses
/// [ref.listen] to react to the result rather than watching the value
/// directly, so navigation happens exactly once.

final class JoinByCodeFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Joined>, String> {
  JoinByCodeFamily._()
    : super(
        retry: null,
        name: r'joinByCodeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Joins a game by invite code, returning the game's id and its roster.
  ///
  /// Auto-disposes once the join screen navigates away. The screen uses
  /// [ref.listen] to react to the result rather than watching the value
  /// directly, so navigation happens exactly once.

  JoinByCodeProvider call({required String code}) =>
      JoinByCodeProvider._(argument: code, from: this);

  @override
  String toString() => r'joinByCodeProvider';
}

/// A finished game's outcomes.
///
/// Immutable once written, and already on the summary - so this is a
/// projection rather than a fetch. Empty while the game is still running.

@ProviderFor(gameOutcomes)
final gameOutcomesProvider = GameOutcomesFamily._();

/// A finished game's outcomes.
///
/// Immutable once written, and already on the summary - so this is a
/// projection rather than a fetch. Empty while the game is still running.

final class GameOutcomesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Outcome>>,
          List<Outcome>,
          FutureOr<List<Outcome>>
        >
    with $FutureModifier<List<Outcome>>, $FutureProvider<List<Outcome>> {
  /// A finished game's outcomes.
  ///
  /// Immutable once written, and already on the summary - so this is a
  /// projection rather than a fetch. Empty while the game is still running.
  GameOutcomesProvider._({
    required GameOutcomesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'gameOutcomesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$gameOutcomesHash();

  @override
  String toString() {
    return r'gameOutcomesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Outcome>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Outcome>> create(Ref ref) {
    final argument = this.argument as String;
    return gameOutcomes(ref, gameId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GameOutcomesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$gameOutcomesHash() => r'2e36f7fd06a516b344538f32f38ef863245f9989';

/// A finished game's outcomes.
///
/// Immutable once written, and already on the summary - so this is a
/// projection rather than a fetch. Empty while the game is still running.

final class GameOutcomesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Outcome>>, String> {
  GameOutcomesFamily._()
    : super(
        retry: null,
        name: r'gameOutcomesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A finished game's outcomes.
  ///
  /// Immutable once written, and already on the summary - so this is a
  /// projection rather than a fetch. Empty while the game is still running.

  GameOutcomesProvider call({required String gameId}) =>
      GameOutcomesProvider._(argument: gameId, from: this);

  @override
  String toString() => r'gameOutcomesProvider';
}

/// A player's most recent finished public games, for the replay list on their
/// profile.
///
/// Works for any player, human or bot. Public and finished only, so it never
/// exposes a game that was not already replayable by anyone holding its id.

@ProviderFor(playerPublicFinishedGames)
final playerPublicFinishedGamesProvider = PlayerPublicFinishedGamesFamily._();

/// A player's most recent finished public games, for the replay list on their
/// profile.
///
/// Works for any player, human or bot. Public and finished only, so it never
/// exposes a game that was not already replayable by anyone holding its id.

final class PlayerPublicFinishedGamesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<GameSummary>>,
          List<GameSummary>,
          FutureOr<List<GameSummary>>
        >
    with
        $FutureModifier<List<GameSummary>>,
        $FutureProvider<List<GameSummary>> {
  /// A player's most recent finished public games, for the replay list on their
  /// profile.
  ///
  /// Works for any player, human or bot. Public and finished only, so it never
  /// exposes a game that was not already replayable by anyone holding its id.
  PlayerPublicFinishedGamesProvider._({
    required PlayerPublicFinishedGamesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'playerPublicFinishedGamesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$playerPublicFinishedGamesHash();

  @override
  String toString() {
    return r'playerPublicFinishedGamesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<GameSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<GameSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return playerPublicFinishedGames(ref, playerId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PlayerPublicFinishedGamesProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$playerPublicFinishedGamesHash() =>
    r'75eaf75a9b4b3f2d4b7cb424f2f09cb59f1ac449';

/// A player's most recent finished public games, for the replay list on their
/// profile.
///
/// Works for any player, human or bot. Public and finished only, so it never
/// exposes a game that was not already replayable by anyone holding its id.

final class PlayerPublicFinishedGamesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<GameSummary>>, String> {
  PlayerPublicFinishedGamesFamily._()
    : super(
        retry: null,
        name: r'playerPublicFinishedGamesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A player's most recent finished public games, for the replay list on their
  /// profile.
  ///
  /// Works for any player, human or bot. Public and finished only, so it never
  /// exposes a game that was not already replayable by anyone holding its id.

  PlayerPublicFinishedGamesProvider call({required String playerId}) =>
      PlayerPublicFinishedGamesProvider._(argument: playerId, from: this);

  @override
  String toString() => r'playerPublicFinishedGamesProvider';
}

// **************************************************************************
// JsonGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
abstract class _$AvailableBots extends _$AvailableBotsBase {
  /// The default key used by [persist].
  String get key {
    const resolvedKey = "AvailableBots";
    return resolvedKey;
  }

  /// A variant of [persist], for JSON-specific encoding.
  ///
  /// You can override [key] to customize the key used for storage.
  PersistResult persist(
    FutureOr<Storage<String, String>> storage, {
    String? key,
    String Function(List<Bot> state)? encode,
    List<Bot> Function(String encoded)? decode,
    StorageOptions options = const StorageOptions(),
  }) {
    return NotifierPersistX(this).persist<String, String>(
      storage,
      key: key ?? this.key,
      encode: encode ?? $jsonCodex.encode,
      decode:
          decode ??
          (encoded) {
            final e = $jsonCodex.decode(encoded);
            return (e as List)
                .map((e) => Bot.fromJson(e as Map<String, Object?>))
                .toList();
          },
      options: options,
    );
  }
}
