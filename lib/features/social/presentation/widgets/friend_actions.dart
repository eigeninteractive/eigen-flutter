import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_flutter/core/updates/required_update_button.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:eigen_flutter/features/social/presentation/widgets/friend_buttons.dart';
import 'package:eigen_flutter/features/social/providers/social_providers.dart';

/// Derives the current friendship status between the signed-in user and
/// [playerId] and renders the appropriate action button(s).
///
/// Returns [SizedBox.shrink] when [playerId] is the current user.
///
/// Self-gates when the viewer is an anonymous guest, since the server rejects all
/// friend writes from guests, so instead of action buttons a guest sees a
/// sign-in hint that routes to the account-upgrade flow in settings (or
/// nothing, when [compact]). Gating here rather than in each parent keeps
/// every embedding correct by construction.
///
/// Each button owns its mutation state machine, so this widget only needs
/// to route on [FriendStatus], with no mutation watching or coordination needed.
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
    final currentUserId = ref.watch(currentUserIdProvider);
    if (playerId == currentUserId) return const SizedBox.shrink();

    if (ref.watch(isAnonymousProvider)) {
      return compact ? const SizedBox.shrink() : const _GuestSignInHint();
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

/// Guest replacement for friend actions: the sign-in hint plus a button
/// routing to the settings screen, where the account-upgrade card lives.
/// Mirrors the "Sign in" treatment on the lobby's locked friends tab.
class _GuestSignInHint extends StatelessWidget {
  const _GuestSignInHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sign in to add friends.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () {
            final router = GoRouter.of(context);
            // The enclosing profile sheet lives on the presenting navigator
            // and would stay up over the settings tab; dismiss it first.
            final navigator = Navigator.of(context);
            if (navigator.canPop()) navigator.pop();
            router.goNamed('settings');
          },
          child: const Text('Sign in'),
        ),
      ],
    );
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
      FriendStatus.updateRequired => const Center(
        child: RequiredUpdateButton(),
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
      FriendStatus.updateRequired => const RequiredUpdateButton(compact: true),
    };
  }
}
