import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:eigen_flutter/core/errors/error_messages.dart';
import 'package:eigen_flutter/core/notifications/firebase_notification_service.dart';
import 'package:eigen_flutter/core/notifications/notification_provider.dart';
import 'package:eigen_flutter/core/theme/theme_provider.dart';
import 'package:eigen_flutter/core/utils/deep_links.dart';
import 'package:eigen_flutter/core/utils/package_info_provider.dart';
import 'package:eigen_flutter/features/auth/providers/auth_providers.dart';
import 'package:eigen_flutter/shared/providers/player_providers.dart';
import 'package:eigen_flutter/shared/widgets/player_avatar.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings screen with navigation to profile and app settings.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final appHost = ref.watch(appConfigProvider).engine.appHost;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Profile Section
        const _SectionHeader(title: 'Account'),
        if (ref.watch(isAnonymousProvider)) const _UpgradeAccountCard(),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const _ProfileAvatarLeading(),
            title: const Text('Edit Profile'),
            subtitle: const Text('Update your profile details'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/profile'),
          ),
        ),
        const SizedBox(height: 16),

        // Preferences Section
        const _SectionHeader(title: 'Preferences'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              _ThemeSelector(),
              const Divider(height: 1),
              const _NotificationsSection(),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // About Section
        const _SectionHeader(title: 'About'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              const _AppVersionTile(),
              if (appHost != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.description_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchLegalUrl('/terms', appHost: appHost),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.privacy_tip_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchLegalUrl('/privacy', appHost: appHost),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 32),

        const _DeleteAccountTile(),

        const SizedBox(height: 32),

        const _AppInfoFooter(),

        const SizedBox(height: 16),
      ],
    );
  }
}

/// Notification settings section. Shows permission status and per-category
/// descriptions when enabled; prompts to enable or open Settings when not.
class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusAsync = ref.watch(notificationPermissionStatusProvider);

    return statusAsync.when(
      loading: () => ListTile(
        leading: Icon(
          Icons.notifications_outlined,
          color: colorScheme.onSurfaceVariant,
        ),
        title: const Text('Notifications'),
        subtitle: const LinearProgressIndicator(),
      ),
      error: (_, _) => ListTile(
        leading: Icon(
          Icons.notifications_outlined,
          color: colorScheme.onSurfaceVariant,
        ),
        title: const Text('Notifications'),
        subtitle: const Text('Could not check permission status'),
      ),
      data: (status) => switch (status) {
        NotificationPermissionState.unavailable => const _UnavailableTile(),
        NotificationPermissionState.promptable => const _NotDeterminedTile(),
        NotificationPermissionState.enabled => const _EnabledSection(),
        NotificationPermissionState.blocked => const _DeniedTile(),
      },
    );
  }
}

/// Shown when this browser lacks Web Push support.
class _UnavailableTile extends StatelessWidget {
  const _UnavailableTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.notifications_off_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: const Text('Notifications'),
      subtitle: const Text('Notifications aren’t available here'),
    );
  }
}

/// Shown when notifications are granted. Lists the categories so the
/// user knows what each channel controls; a link opens system settings for
/// per-channel management (Android) or the app settings page (iOS).
class _EnabledSection extends StatelessWidget {
  const _EnabledSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ListTile(
          leading: Icon(
            Icons.notifications_active_outlined,
            color: colorScheme.primary,
          ),
          title: const Text('Notifications'),
          subtitle: Text(
            kIsWeb ? 'Enabled in this browser' : 'Tap to manage in Settings',
          ),
          trailing: kIsWeb ? null : const Icon(Icons.chevron_right, size: 18),
          onTap: kIsWeb
              ? null
              : () => AppSettings.openAppSettings(
                  type: AppSettingsType.notification,
                ),
        ),
        const Divider(height: 1, indent: 56),
        const _CategoryRow(
          icon: Icons.sports_esports_outlined,
          label: 'Your Turn',
          description: 'When it\'s your move in a game',
        ),
        const _CategoryRow(
          icon: Icons.emoji_events_outlined,
          label: 'Game Updates',
          description: 'When a game starts or finishes',
        ),
        const _CategoryRow(
          icon: Icons.group_add_outlined,
          label: 'Game Invites',
          description: 'When a friend starts a game for you',
        ),
        const _CategoryRow(
          icon: Icons.people_outline,
          label: 'Social & Friends',
          description: 'Friend requests and accepts',
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Shown when the user has explicitly denied notifications.
class _DeniedTile extends StatelessWidget {
  const _DeniedTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.notifications_off_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: const Text('Notifications'),
      subtitle: Text(
        kIsWeb
            ? 'Blocked — enable notifications in this site’s browser settings'
            : 'Disabled — tap to open Settings',
      ),
      trailing: kIsWeb ? null : const Icon(Icons.open_in_new, size: 18),
      onTap: kIsWeb
          ? null
          : () =>
                AppSettings.openAppSettings(type: AppSettingsType.notification),
    );
  }
}

/// Shown when the user has not yet been asked for permission.
class _NotDeterminedTile extends ConsumerStatefulWidget {
  const _NotDeterminedTile();

  @override
  ConsumerState<_NotDeterminedTile> createState() => _NotDeterminedTileState();
}

class _NotDeterminedTileState extends ConsumerState<_NotDeterminedTile> {
  bool _requesting = false;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.notifications_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: const Text('Notifications'),
      subtitle: const Text('Stay updated with game alerts'),
      trailing: FilledButton.tonal(
        onPressed: _requesting ? null : _requestPermission,
        child: _requesting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Enable'),
      ),
    );
  }

  Future<void> _requestPermission() async {
    setState(() => _requesting = true);
    try {
      final state = await ref
          .read(notificationServiceProvider)
          .requestPermission();
      if (!mounted) return;
      switch (state) {
        case NotificationPermissionState.blocked:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notifications weren’t enabled.')),
          );
        case NotificationPermissionState.unavailable:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notifications aren’t available here.'),
            ),
          );
        case NotificationPermissionState.promptable ||
            NotificationPermissionState.enabled:
          break;
      }
    } on NotificationRegistrationException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permission was granted, but notification setup didn’t finish. '
            'We’ll retry automatically.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not enable notifications. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        ref.invalidate(notificationPermissionStatusProvider);
        setState(() => _requesting = false);
      }
    }
  }
}

/// A single notification category row displayed when notifications are enabled.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.icon,
    required this.label,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppVersionTile extends ConsumerWidget {
  const _AppVersionTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final infoAsync = ref.watch(packageInfoProvider);

    return ListTile(
      leading: Icon(Icons.info_outline, color: colorScheme.onSurfaceVariant),
      title: const Text('App Version'),
      subtitle: infoAsync.when(
        data: (info) => Text(info.version),
        loading: () => const Text('...'),
        error: (_, _) => const Text('Unknown'),
      ),
    );
  }
}

class _AppInfoFooter extends ConsumerWidget {
  const _AppInfoFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credit = ref.watch(appConfigProvider).branding.madeByCredit;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        credit,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Theme selector widget with Material 3 SegmentedButton.
class _ThemeSelector extends ConsumerWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAsync = ref.watch(themeControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.palette_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Text('Theme', style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
          const SizedBox(height: 12),
          themeAsync.when(
            data: (currentTheme) => SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.phone_android_outlined),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark'),
                  ),
                ],
                selected: {currentTheme},
                onSelectionChanged: (selection) {
                  ref
                      .read(themeControllerProvider.notifier)
                      .setTheme(selection.first);
                },
              ),
            ),
            loading: () => const Center(
              child: SizedBox(height: 48, child: CircularProgressIndicator()),
            ),
            error: (_, _) => const Text('Failed to load theme preference'),
          ),
        ],
      ),
    );
  }
}

/// Destructive tile that triggers account deletion after confirmation.
/// Prominent call-to-action shown to guests, prompting them to link a Google
/// account so their games, ratings, and friends are saved permanently.
class _UpgradeAccountCard extends ConsumerWidget {
  const _UpgradeAccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final onContainer = colorScheme.onPrimaryContainer;

    final isLoading = ref.watch(
      authControllerProvider.select((state) => state.isLoading),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_circle, color: onContainer),
                const SizedBox(width: 12),
                Text(
                  'Save your progress',
                  style: textTheme.titleMedium?.copyWith(color: onContainer),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "You're playing as a guest. Create an account to keep your games, "
              'ratings, and friends, and to unlock rated games and social '
              'features.',
              style: textTheme.bodyMedium?.copyWith(color: onContainer),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule_outlined, size: 18, color: onContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Guest data is removed after a few days of inactivity. '
                    'Create an account to keep it for good.',
                    style: textTheme.bodySmall?.copyWith(color: onContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: isLoading ? null : () => _upgrade(context, ref),
                child: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Text('Create account'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _upgrade(BuildContext context, WidgetRef ref) async {
    // Capture before the await — on success this card is removed from the tree
    // (isAnonymous flips false), but the messenger ancestor survives.
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      final outcome = await ref
          .read(authControllerProvider.notifier)
          .upgradeToGoogle();
      switch (outcome) {
        case UpgradeOutcome.linked:
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Account created — your games, ratings, and friends are saved.',
              ),
            ),
          );
        case UpgradeOutcome.existingAccount:
          if (!context.mounted) return;
          final shouldSwitch = await showExistingAccountSwitchDialog(context);
          if (!shouldSwitch) {
            ref
                .read(authControllerProvider.notifier)
                .cancelExistingAccountSwitch();
            return;
          }
          await ref.read(authControllerProvider.notifier).switchToExisting();
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Signed in to your existing account. Guest progress wasn\'t '
                'transferred.',
              ),
            ),
          );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not create account: ${humanize(e)}'),
          backgroundColor: colorScheme.error,
        ),
      );
    }
  }
}

/// Confirms the destructive half of a guest-to-existing-account transition.
///
/// Kept as a separate function so the behavior is directly widget-testable and
/// every caller presents the same warning before guest progress is abandoned.
@visibleForTesting
Future<bool> showExistingAccountSwitchDialog(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sign in to your existing account?'),
          content: const Text(
            'That Google account already exists. You can sign in to it, but '
            'this guest’s games, ratings, and friends cannot be transferred.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep playing as guest'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ) ??
      false;
}

class _DeleteAccountTile extends StatelessWidget {
  const _DeleteAccountTile();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(Icons.delete_forever_outlined, color: colorScheme.error),
        title: Text(
          'Delete Account',
          style: TextStyle(color: colorScheme.error),
        ),
        trailing: Icon(Icons.chevron_right, color: colorScheme.error),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => const _DeleteAccountDialog(),
        ),
      ),
    );
  }
}

/// Confirmation dialog for account deletion.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Delete account?'),
      content: const Text(
        'This permanently deletes your account, all your games, and your '
        'ratings. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: _deleting ? null : _deleteAccount,
          child: _deleting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onError,
                  ),
                )
              : const Text('Delete account'),
        ),
      ],
    );
  }

  Future<void> _deleteAccount() async {
    setState(() => _deleting = true);

    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete account: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

Future<void> _launchLegalUrl(String path, {required String? appHost}) async {
  final uri = legalPageUrl(path, appHost: appHost);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Shows the current user's profile avatar, falling back to a generic icon.
class _ProfileAvatarLeading extends ConsumerWidget {
  const _ProfileAvatarLeading();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      backgroundColor: colorScheme.primaryContainer,
      child: Icon(Icons.person_outline, color: colorScheme.onPrimaryContainer),
    );

    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) return fallback;

    return ref
        .watch(playerInfoCacheProvider(id: currentUser.id))
        .when(
          data: (player) =>
              PlayerAvatar(avatarUrl: player.avatarUrl, radius: 20),
          loading: () => fallback,
          error: (_, _) => fallback,
        );
  }
}

/// Section header widget for settings groups.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
