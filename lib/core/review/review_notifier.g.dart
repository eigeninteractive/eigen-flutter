// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tracks total wins and gates in-app review prompts.
///
/// State is the lifetime win count, persisted across sessions via
/// [SharedPreferences]. A review prompt is requested every [_reviewEveryNWins]
/// wins, regardless of whether the game was rated. The OS enforces its own
/// quota (3× per year on both platforms) and silently no-ops when it is hit.

@ProviderFor(ReviewNotifier)
final reviewProvider = ReviewNotifierProvider._();

/// Tracks total wins and gates in-app review prompts.
///
/// State is the lifetime win count, persisted across sessions via
/// [SharedPreferences]. A review prompt is requested every [_reviewEveryNWins]
/// wins, regardless of whether the game was rated. The OS enforces its own
/// quota (3× per year on both platforms) and silently no-ops when it is hit.
final class ReviewNotifierProvider
    extends $AsyncNotifierProvider<ReviewNotifier, int> {
  /// Tracks total wins and gates in-app review prompts.
  ///
  /// State is the lifetime win count, persisted across sessions via
  /// [SharedPreferences]. A review prompt is requested every [_reviewEveryNWins]
  /// wins, regardless of whether the game was rated. The OS enforces its own
  /// quota (3× per year on both platforms) and silently no-ops when it is hit.
  ReviewNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reviewProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reviewNotifierHash();

  @$internal
  @override
  ReviewNotifier create() => ReviewNotifier();
}

String _$reviewNotifierHash() => r'e0ee98e96c30b19655744ddcd875f38167187a7c';

/// Tracks total wins and gates in-app review prompts.
///
/// State is the lifetime win count, persisted across sessions via
/// [SharedPreferences]. A review prompt is requested every [_reviewEveryNWins]
/// wins, regardless of whether the game was rated. The OS enforces its own
/// quota (3× per year on both platforms) and silently no-ops when it is hit.

abstract class _$ReviewNotifier extends $AsyncNotifier<int> {
  FutureOr<int> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<int>, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<int>, int>,
              AsyncValue<int>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
