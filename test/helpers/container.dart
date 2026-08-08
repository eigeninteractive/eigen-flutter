import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Creates an auto-disposed [ProviderContainer] with the given [overrides].
///
/// Wraps [ProviderContainer.test], which registers `addTearDown(dispose)` so
/// the container is torn down when the test ends.
///
/// Most engine providers need no override. Only graphs reaching
/// `appConfigProvider` or `currentGameModuleProvider` (which throw by default)
/// require one; prefer overriding the *immediate* dependency a test reads
/// (e.g. `friendshipsProvider`) rather than the whole api/auth chain.
ProviderContainer makeContainer({List<Override> overrides = const []}) =>
    ProviderContainer.test(overrides: overrides);
