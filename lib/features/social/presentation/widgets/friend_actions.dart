import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/social/presentation/widgets/friend_buttons.dart';
import 'package:eigen_engine/features/social/providers/social_providers.dart';

/// Derives the current friendship status between the signed-in user and
/// [playerId] and renders the appropriate action button(s).
///
/// Returns [SizedBox.shrink] when [playerId] is the current user.
///
/// Self-gates when the viewer is an anonymous guest — the server rejects all
/// friend writes from guests, so instead of action buttons a guest sees a
/// sign-in hint (or nothing, when [compact]). Gating here rather than in each
/// parent keeps every embedding correct by construction.
///
/// Each button owns its mutation state machine, so this widget only needs
/// to route on [FriendStatus] — no mutation watching or coordination needed.
///
/// [compact] true is suited for search-result list tile trailing (single small
/// button). [compact] false (default) is suited for a profile sheet
/// (centered row of full-size buttons).
class FriendActions extends ConsumerWidget {
  const FriendActions({
    super.key,
    required this.playerId,
    this.compact = false,
  });

  final String playerId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(authServiceProvider).currentUser?.id;
    if (playerId == currentUserId) return const SizedBox.shrink();

    if (ref.watch(isAnonymousProvider)) {
      return compact
          ? const SizedBox.shrink()
          : Center(
              child: Text(
                'Sign in to add friends.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
    }

    final statusAsync = ref.watch(friendStatusProvider(targetId: playerId));

    // Show spinner only on initial load (no cached value yet).
    // During reload (hasValue is true), show the previous status to avoid a
    // different-sized spinner flickering while friendStatusProvider reloads.
    if (!statusAsync.hasValue) {
      if (statusAsync.hasError) {
        return compact
            ? const SizedBox.shrink()
            : Center(
                child: Text(
                  'Could not load friendship status',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              );
      }
      return compact
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Center(child: CircularProgressIndicator());
    }

    final status = statusAsync.value ?? FriendStatus.none;

    return compact
        ? _CompactActions(playerId: playerId, status: status)
        : _FullActions(playerId: playerId, status: status);
  }
}

// ── Profile sheet layout ──────────────────────────────────────────────────────

class _FullActions extends StatelessWidget {
  const _FullActions({required this.playerId, required this.status});

  final String playerId;
  final FriendStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      FriendStatus.none => Center(child: SendRequestButton(playerId: playerId)),
      FriendStatus.outgoingPending => const Center(
        child: OutlinedButton(onPressed: null, child: Text('Request sent')),
      ),
      FriendStatus.incomingPending => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AcceptRequestButton(playerId: playerId),
          const SizedBox(width: 12),
          DeclineRequestButton(playerId: playerId),
        ],
      ),
      FriendStatus.friends => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FilledButton.tonal(onPressed: null, child: Text('Friends')),
          const SizedBox(width: 12),
          RemoveFriendButton(playerId: playerId),
        ],
      ),
    };
  }
}

// ── Search-result list tile layout ────────────────────────────────────────────

class _CompactActions extends StatelessWidget {
  const _CompactActions({required this.playerId, required this.status});

  final String playerId;
  final FriendStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      FriendStatus.none => SendRequestButton(playerId: playerId, compact: true),
      FriendStatus.outgoingPending => const OutlinedButton(
        onPressed: null,
        child: Text('Sent'),
      ),
      FriendStatus.incomingPending => AcceptRequestButton(
        playerId: playerId,
        compact: true,
      ),
      FriendStatus.friends => const FilledButton.tonal(
        onPressed: null,
        child: Text('Friends'),
      ),
    };
  }
}
