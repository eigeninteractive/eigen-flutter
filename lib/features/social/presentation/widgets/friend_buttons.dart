import 'package:flutter/material.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_flutter/core/errors/error_messages.dart';
import 'package:eigen_flutter/features/social/providers/social_providers.dart';

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner({this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(strokeWidth: 2),
  );
}

/// Sends a friend request to [playerId].
///
/// [compact] true renders a tonal button labelled "Add"; false (default)
/// renders a filled button labelled "Add Friend".
///
/// Shows "Sent"/"Request Sent" while the provider re-fetches after a successful
/// send, bridging the gap without coordination logic in the parent widget.
class SendRequestButton extends ConsumerWidget {
  const SendRequestButton({
    super.key,
    required this.playerId,
    this.compact = false,
  });

  final String playerId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(Friends.send(playerId), (_, next) {
      if (next is MutationError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanize(next.error))));
      }
    });

    void send() => Friends.send(playerId)
        .run(
          ref,
          (tsx) async =>
              tsx.get(friendsProvider.notifier).sendRequest(playerId),
        )
        .ignore();

    return switch (ref.watch(Friends.send(playerId))) {
      MutationIdle() =>
        compact
            ? FilledButton.tonal(onPressed: send, child: const Text('Add'))
            : FilledButton(onPressed: send, child: const Text('Add Friend')),
      MutationPending() =>
        compact
            ? FilledButton.tonal(onPressed: null, child: const _ButtonSpinner())
            : FilledButton(onPressed: null, child: const _ButtonSpinner()),
      MutationSuccess() =>
        compact
            ? const OutlinedButton(onPressed: null, child: Text('Sent'))
            : const OutlinedButton(
                onPressed: null,
                child: Text('Request Sent'),
              ),
      MutationError() =>
        compact
            ? FilledButton.tonal(onPressed: send, child: const Text('Retry'))
            : FilledButton(onPressed: send, child: const Text('Retry')),
    };
  }
}

/// Accepts an incoming friend request from [playerId].
///
/// [compact] true renders an icon button; false (default) renders a filled
/// button labelled "Accept".
class AcceptRequestButton extends ConsumerWidget {
  const AcceptRequestButton({
    super.key,
    required this.playerId,
    this.compact = false,
  });

  final String playerId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(Friends.accept(playerId), (_, next) {
      if (next is MutationError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanize(next.error))));
      }
    });

    void accept() => Friends.accept(playerId)
        .run(
          ref,
          (tsx) async =>
              tsx.get(friendsProvider.notifier).acceptRequest(playerId),
        )
        .ignore();

    final colorScheme = Theme.of(context).colorScheme;

    return switch (ref.watch(Friends.accept(playerId))) {
      MutationIdle() =>
        compact
            ? IconButton(
                icon: Icon(Icons.check, color: colorScheme.primary),
                onPressed: accept,
              )
            : FilledButton(onPressed: accept, child: const Text('Accept')),
      MutationPending() =>
        compact
            ? IconButton(icon: const _ButtonSpinner(size: 20), onPressed: null)
            : FilledButton(onPressed: null, child: const _ButtonSpinner()),
      MutationSuccess() =>
        compact
            ? IconButton(
                icon: Icon(Icons.check, color: colorScheme.primary),
                onPressed: null,
              )
            : const FilledButton(onPressed: null, child: Text('Accepted')),
      MutationError() =>
        compact
            ? IconButton(
                icon: Icon(Icons.refresh, color: colorScheme.error),
                onPressed: accept,
              )
            : FilledButton(onPressed: accept, child: const Text('Retry')),
    };
  }
}

/// Declines an incoming friend request from [playerId]. No confirm dialog.
///
/// [compact] true renders an icon button; false (default) renders an outlined
/// button labelled "Decline".
class DeclineRequestButton extends ConsumerWidget {
  const DeclineRequestButton({
    super.key,
    required this.playerId,
    this.compact = false,
  });

  final String playerId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(Friends.remove(playerId), (_, next) {
      if (next is MutationError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanize(next.error))));
      }
    });

    void decline() => Friends.remove(playerId)
        .run(
          ref,
          (tsx) async =>
              tsx.get(friendsProvider.notifier).removeFriend(playerId),
        )
        .ignore();

    final colorScheme = Theme.of(context).colorScheme;

    return switch (ref.watch(Friends.remove(playerId))) {
      MutationIdle() =>
        compact
            ? IconButton(
                icon: Icon(Icons.close, color: colorScheme.error),
                onPressed: decline,
              )
            : OutlinedButton(onPressed: decline, child: const Text('Decline')),
      MutationPending() || MutationSuccess() =>
        compact
            ? IconButton(icon: const _ButtonSpinner(size: 20), onPressed: null)
            : const OutlinedButton(onPressed: null, child: _ButtonSpinner()),
      MutationError() =>
        compact
            ? IconButton(
                icon: Icon(Icons.close, color: colorScheme.error),
                onPressed: decline,
              )
            : OutlinedButton(onPressed: decline, child: const Text('Decline')),
    };
  }
}

/// Removes [playerId] as a friend. Shows a confirmation dialog before acting.
///
/// [compact] true renders an icon button; false (default) renders a text
/// button labelled "Remove".
class RemoveFriendButton extends ConsumerStatefulWidget {
  const RemoveFriendButton({
    super.key,
    required this.playerId,
    this.compact = false,
  });

  final String playerId;
  final bool compact;

  @override
  ConsumerState<RemoveFriendButton> createState() => _RemoveFriendButtonState();
}

class _RemoveFriendButtonState extends ConsumerState<RemoveFriendButton> {
  // Guards against the dialog opening twice on rapid double-tap.
  // Not UI state, so no setState needed.
  bool _confirming = false;

  Future<void> _remove() async {
    if (_confirming) return;
    _confirming = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove friend?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      Friends.remove(widget.playerId)
          .run(
            ref,
            (tsx) async =>
                tsx.get(friendsProvider.notifier).removeFriend(widget.playerId),
          )
          .ignore();
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(Friends.remove(widget.playerId), (_, next) {
      if (next is MutationError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanize(next.error))));
      }
    });

    final mutState = ref.watch(Friends.remove(widget.playerId));
    final disabled = _confirming || mutState.isPending;

    return switch (mutState) {
      MutationIdle() || MutationError() =>
        widget.compact
            ? IconButton(
                icon: const Icon(Icons.person_remove),
                onPressed: disabled ? null : _remove,
              )
            : TextButton(
                onPressed: disabled ? null : _remove,
                child: const Text('Remove'),
              ),
      MutationPending() || MutationSuccess() =>
        widget.compact
            ? IconButton(icon: const _ButtonSpinner(size: 20), onPressed: null)
            : const TextButton(onPressed: null, child: _ButtonSpinner()),
    };
  }
}
