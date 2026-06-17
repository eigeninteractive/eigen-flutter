import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_engine/core/config/app_config.dart';
import 'package:eigen_engine/core/utils/package_info_provider.dart';
import 'package:eigen_engine/features/game/providers/game_frame_provider.dart';

/// About page: app identity, the active game's rules, and version/credit.
///
/// A top-level shell destination, so it relies on the shell scaffold for its
/// [AppBar]; the body is a bare [ListView] (same convention as the settings
/// screen). The rules content is supplied by the active game via
/// [GameModule.buildRules].
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appName = ref.watch(appConfigProvider).branding.appName;
    final rules = ref.watch(currentGameModuleProvider).buildRules(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _AppHeader(appName: appName),
        const SizedBox(height: 16),
        const _SectionHeader(title: 'How to Play'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Padding(padding: const EdgeInsets.all(16), child: rules),
        ),
        const SizedBox(height: 16),
        const _SectionHeader(title: 'About'),
        const Card(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _AppVersionTile(),
        ),
        const SizedBox(height: 32),
        const _AppInfoFooter(),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Centered app name shown at the top of the page.
class _AppHeader extends StatelessWidget {
  const _AppHeader({required this.appName});

  final String appName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(
        appName,
        style: Theme.of(context).textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// App version tile, mirroring the one on the settings screen.
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

/// Centered credit line shown at the bottom of the page.
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

/// Section header, matching the settings screen grouping style.
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
