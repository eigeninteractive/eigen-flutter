import 'package:checks/checks.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/shared/data/player_batch_loader.dart';
import 'package:eigen_flutter/shared/data/player_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Player _player(String id) => Player(
  id: id,
  username: id,
  displayName: id,
  avatarUrl: null,
  isAnonymous: false,
);

/// Records every batch it is asked to fetch, and returns players for the ids
/// it was told exist (unknown ids are simply omitted, like the real endpoint).
class _RecordingFetch {
  _RecordingFetch({Set<String>? missing}) : _missing = missing ?? const {};

  final Set<String> _missing;
  final List<List<String>> calls = [];
  Object? error;

  Future<List<Player>> call(List<String> ids) async {
    calls.add(ids);
    if (error != null) throw error!;
    return [
      for (final id in ids)
        if (!_missing.contains(id)) _player(id),
    ];
  }
}

void main() {
  group('PlayerBatchLoader', () {
    test('coalesces every load in one window into a single request', () async {
      final fetch = _RecordingFetch();
      final loader = PlayerBatchLoader(fetch.call);

      final results = await Future.wait([
        loader.load('a'),
        loader.load('b'),
        loader.load('c'),
      ]);

      check(fetch.calls).length.equals(1);
      check(fetch.calls.single).unorderedEquals(['a', 'b', 'c']);
      check(results.map((p) => p.id)).deepEquals(['a', 'b', 'c']);
    });

    test('requests each id once even when loaded twice in a window', () async {
      final fetch = _RecordingFetch();
      final loader = PlayerBatchLoader(fetch.call);

      final futures = [loader.load('a'), loader.load('a'), loader.load('b')];
      final results = await Future.wait(futures);

      check(fetch.calls.single).unorderedEquals(['a', 'b']);
      // Both waiters for 'a' resolve to the same identity.
      check(results[0].id).equals('a');
      check(results[1].id).equals('a');
    });

    test(
      'maps an absent id to PlayerNotFoundException for that waiter only',
      () async {
        final fetch = _RecordingFetch(missing: {'gone'});
        final loader = PlayerBatchLoader(fetch.call);

        final present = loader.load('here');
        final absent = loader.load('gone');

        check((await present).id).equals('here');
        final error = await absent.then<Object?>(
          (_) => null,
          onError: (e) => e,
        );
        check(error)
            .isA<PlayerNotFoundException>()
            .has((e) => e.playerId, 'id')
            .equals('gone');
        // One request served both outcomes.
        check(fetch.calls).length.equals(1);
      },
    );

    test('fails every waiter in the batch when the request throws', () async {
      final fetch = _RecordingFetch()..error = StateError('offline');
      final loader = PlayerBatchLoader(fetch.call);

      // Both issued before awaiting, so they share one window.
      final aFuture = loader.load('a');
      final bFuture = loader.load('b');
      final aError = await aFuture.then<Object?>(
        (_) => null,
        onError: (e) => e,
      );
      final bError = await bFuture.then<Object?>(
        (_) => null,
        onError: (e) => e,
      );

      check(aError).isA<StateError>();
      check(bError).isA<StateError>();
      check(fetch.calls).length.equals(1);
    });

    test('dispose cancels a pending flush before it fires', () async {
      final fetch = _RecordingFetch();
      final loader = PlayerBatchLoader(
        fetch.call,
        window: const Duration(milliseconds: 20),
      );

      // ignore: unawaited_futures, since the waiter intentionally never resolves
      // once the flush is cancelled; we only assert the request never fires.
      loader.load('a');
      loader.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      check(fetch.calls).isEmpty();
    });

    test('starts a fresh batch for loads in a later turn', () async {
      final fetch = _RecordingFetch();
      final loader = PlayerBatchLoader(fetch.call);

      await loader.load('a');
      await loader.load('b');

      check(fetch.calls).deepEquals([
        ['a'],
        ['b'],
      ]);
    });
  });
}
