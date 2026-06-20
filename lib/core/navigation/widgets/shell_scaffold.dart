import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_engine/core/config/app_config.dart';
import 'package:eigen_engine/core/connectivity/connectivity_provider.dart';
import 'package:eigen_engine/shared/widgets/status_banner.dart';
import 'package:eigen_engine/core/updates/update_notifier.dart';
import 'package:eigen_engine/features/auth/providers/auth_providers.dart';
import 'package:eigen_engine/features/game/presentation/widgets/new_game_dialog.dart';
import 'package:eigen_engine/features/game/presentation/widgets/play_vs_bot_dialog.dart';
import 'package:eigen_engine/features/game/providers/game_providers.dart';
import 'package:eigen_engine/features/social/providers/social_providers.dart';

enum _ShellBranch {
  home(''),
  lobby('Game Lobby'),
  history('History'),
  social('Social'),
  about('About'),
  settings('Settings');

  const _ShellBranch(this.title);

  final String title;
}

/// Shell scaffold that wraps all routes with persistent navigation.
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({required this.navigationShell, super.key});

  /// The navigation shell and container for the branch Navigators.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(updateProvider, (_, next) {
      if (next == UpdateInstallStatus.downloadComplete) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('A new version is ready.'),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Restart',
              onPressed: () =>
                  ref.read(updateProvider.notifier).completeUpdate(),
            ),
          ),
        );
      }
    });
    final isOffline = ref.watch(isOfflineProvider);
    final isGuest = ref.watch(isAnonymousProvider);
    // Offer solo play only when a playable combination exists — an untimed mode
    // with a usable local bot, or a timed mode with a usable server bot (so the
    // name is "solo", not "local bots": both classes can fill the seats). See
    // [soloPlayAvailableProvider]. Most deployments with no bots get an empty
    // catalog → no extra FAB.
    final canPlaySolo = ref.watch(soloPlayAvailableProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final index = navigationShell.currentIndex;
    final branch = _ShellBranch.values[index];
    final title = branch.title;

    return Scaffold(
      appBar: AppBar(
        title: title.isEmpty ? null : Text(title),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      drawer: NavigationDrawer(
        selectedIndex: index,
        onDestinationSelected: (int i) {
          Navigator.of(context).pop();
          navigationShell.goBranch(i, initialLocation: i == index);
        },
        children: [
          const _DrawerHeader(),
          const NavigationDrawerDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: Text('Home'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: Text('Lobby'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: Text('History'),
          ),
          // Social is registered-only. For guests the destination stays visible
          // but disabled (greyed, non-tappable) — the same visible-but-disabled
          // treatment rated games get in the lobby. enabled:false also keeps the
          // tap from firing onDestinationSelected, so branch indices stay 1:1.
          NavigationDrawerDestination(
            enabled: !isGuest,
            icon: const _SocialDrawerIcon(selected: false),
            selectedIcon: const _SocialDrawerIcon(selected: true),
            label: const Text('Social'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info_rounded),
            label: Text('About'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: Text('Settings'),
          ),
          const _SignOutButton(),
        ],
      ),
      floatingActionButton: index == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (canPlaySolo) ...[
                  FloatingActionButton.extended(
                    heroTag: 'newSoloGame',
                    onPressed: () => showDialog(
                      context: context,
                      useSafeArea: true,
                      builder: (_) => const PlayVsBotDialog(),
                    ),
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('New Solo Game'),
                  ),
                  const SizedBox(height: 12),
                ],
                FloatingActionButton.extended(
                  heroTag: 'newGame',
                  onPressed: () => showDialog(
                    context: context,
                    useSafeArea: true,
                    builder: (_) => const NewGameDialog(),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('New Game'),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: isOffline ? const _OfflineBanner() : const SizedBox.shrink(),
          ),
          Expanded(child: SafeArea(child: navigationShell)),
        ],
      ),
    );
  }
}

/// Slim banner shown when the device has no network connectivity.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return StatusBanner(
      leading: Icon(
        Icons.wifi_off_rounded,
        size: 16,
        color: colorScheme.onErrorContainer,
      ),
      label: 'No internet connection',
      backgroundColor: colorScheme.errorContainer,
      foregroundColor: colorScheme.onErrorContainer,
    );
  }
}

/// Drawer header widget.
class _DrawerHeader extends ConsumerWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: Text(
        ref.watch(appConfigProvider).branding.appName,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}

/// Social icon with a badge showing the number of incoming friend requests.
class _SocialDrawerIcon extends ConsumerWidget {
  const _SocialDrawerIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = switch (ref.watch(pendingRequestsProvider)) {
      AsyncData(:final value) => value.length,
      _ => 0,
    };
    final icon = Icon(selected ? Icons.people_rounded : Icons.people_outline);
    if (count > 0) {
      return Badge.count(count: count, child: icon);
    }
    return icon;
  }
}

/// Sign out button widget.
class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 48),
      child: OutlinedButton.icon(
        onPressed: () async {
          Scaffold.of(context).closeDrawer();
          await ref.read(authControllerProvider.notifier).signOut();
        },
        icon: const Icon(Icons.logout),
        label: const Text('Sign Out'),
      ),
    );
  }
}
