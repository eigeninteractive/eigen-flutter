import 'package:eigen_flutter/core/updates/app_update_gateway.dart';
import 'package:eigen_flutter/core/updates/update_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs the available update action for compatibility-blocked UI.
class RequiredUpdateButton extends ConsumerStatefulWidget {
  const RequiredUpdateButton({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<RequiredUpdateButton> createState() =>
      _RequiredUpdateButtonState();
}

class _RequiredUpdateButtonState extends ConsumerState<RequiredUpdateButton> {
  bool _requesting = false;

  Future<void> _requestUpdate() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    final result = await ref
        .read(updateProvider.notifier)
        .requestRequiredUpdate();
    if (!mounted) return;
    setState(() => _requesting = false);

    final message = switch (result) {
      RequiredUpdateResult.started => null,
      RequiredUpdateResult.declined => 'Update cancelled. You can try again.',
      RequiredUpdateResult.unavailable =>
        'No Play update is available yet. Please try again soon.',
      RequiredUpdateResult.failed =>
        ref.read(appUpdateGatewayProvider).platform == ClientUpdatePlatform.web
            ? 'Could not reload the app. Please reload your browser.'
            : 'Could not start the update. Please try again.',
    };
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(appUpdateGatewayProvider).platform;
    if (platform == ClientUpdatePlatform.unsupported) {
      return const SizedBox.shrink();
    }
    final isWeb = platform == ClientUpdatePlatform.web;
    final icon = _requesting
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.system_update);
    final label = Text(
      _requesting
          ? (isWeb ? 'Reloading…' : 'Checking…')
          : (isWeb ? 'Reload App' : 'Update App'),
    );

    if (widget.compact) {
      return FilledButton.tonalIcon(
        onPressed: _requesting ? null : _requestUpdate,
        icon: icon,
        label: label,
      );
    }
    return FilledButton.icon(
      onPressed: _requesting ? null : _requestUpdate,
      icon: icon,
      label: label,
    );
  }
}
