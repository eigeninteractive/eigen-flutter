// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rating_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ratingRepository)
final ratingRepositoryProvider = RatingRepositoryProvider._();

final class RatingRepositoryProvider
    extends
        $FunctionalProvider<
          RatingRepository,
          RatingRepository,
          RatingRepository
        >
    with $Provider<RatingRepository> {
  RatingRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ratingRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ratingRepositoryHash();

  @$internal
  @override
  $ProviderElement<RatingRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RatingRepository create(Ref ref) {
    return ratingRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RatingRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RatingRepository>(value),
    );
  }
}

String _$ratingRepositoryHash() => r'4d91be5d7c2842b5a96c2687d90b3835add2c74c';

/// All pool ratings for [id], ordered by highest display rating.
///
/// Works for both human user IDs and bot IDs.

@ProviderFor(playerRatings)
final playerRatingsProvider = PlayerRatingsFamily._();

/// All pool ratings for [id], ordered by highest display rating.
///
/// Works for both human user IDs and bot IDs.

final class PlayerRatingsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Rating>>,
          List<Rating>,
          FutureOr<List<Rating>>
        >
    with $FutureModifier<List<Rating>>, $FutureProvider<List<Rating>> {
  /// All pool ratings for [id], ordered by highest display rating.
  ///
  /// Works for both human user IDs and bot IDs.
  PlayerRatingsProvider._({
    required PlayerRatingsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'playerRatingsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$playerRatingsHash();

  @override
  String toString() {
    return r'playerRatingsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Rating>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Rating>> create(Ref ref) {
    final argument = this.argument as String;
    return playerRatings(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PlayerRatingsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$playerRatingsHash() => r'71c55d167dd0f7d2ff7220b1c26d53eb0ca964c4';

/// All pool ratings for [id], ordered by highest display rating.
///
/// Works for both human user IDs and bot IDs.

final class PlayerRatingsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Rating>>, String> {
  PlayerRatingsFamily._()
    : super(
        retry: null,
        name: r'playerRatingsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// All pool ratings for [id], ordered by highest display rating.
  ///
  /// Works for both human user IDs and bot IDs.

  PlayerRatingsProvider call(String id) =>
      PlayerRatingsProvider._(argument: id, from: this);

  @override
  String toString() => r'playerRatingsProvider';
}

/// Current user's ratings across all pools.
///
/// Auto-disposes when the profile screen is not visible, so navigation
/// to the profile page always fetches fresh data.

@ProviderFor(myRatings)
final myRatingsProvider = MyRatingsProvider._();

/// Current user's ratings across all pools.
///
/// Auto-disposes when the profile screen is not visible, so navigation
/// to the profile page always fetches fresh data.

final class MyRatingsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Rating>>,
          List<Rating>,
          FutureOr<List<Rating>>
        >
    with $FutureModifier<List<Rating>>, $FutureProvider<List<Rating>> {
  /// Current user's ratings across all pools.
  ///
  /// Auto-disposes when the profile screen is not visible, so navigation
  /// to the profile page always fetches fresh data.
  MyRatingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myRatingsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myRatingsHash();

  @$internal
  @override
  $FutureProviderElement<List<Rating>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Rating>> create(Ref ref) {
    return myRatings(ref);
  }
}

String _$myRatingsHash() => r'7018d5182c0e8833e2410b52427155196d7973c0';
