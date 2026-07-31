import 'package:app_settings/app_settings.dart';
import 'package:eigen_flutter/core/notifications/firebase_notification_service.dart';
import 'package:eigen_flutter/core/notifications/notification_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Contextual notification onboarding for a seated multiplayer participant.
///
/// A non-modal card explains the value before any system prompt. A denied
/// permission becomes platform-appropriate recovery guidance.
class GameNotificationNudge extends ConsumerStatefulWidget {
  const GameNotificationNudge({super.key});

  @override
  ConsumerState<GameNotificationNudge> createState() =>
      _GameNotificationNudgeState();
}

class _GameNotificationNudgeState extends ConsumerState<GameNotificationNudge> {
  bool _requesting = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationNudgeProvider).value;

    return switch (state) {
      NotificationNudgeState.enable => _EnableCard(
        requesting: _requesting,
        onEnable: _requestPermission,
      ),
      NotificationNudgeState.openSettings => const _OpenSettingsCard(),
      NotificationNudgeState.hidden || null => const SizedBox.shrink(),
    };
  }

  Future<bool> _requestPermission() async {
    if (_requesting) return false;
    setState(() => _requesting = true);
    try {
      final state = await ref
          .read(notificationServiceProvider)
          .requestPermission();
      if (!mounted) return state == NotificationPermissionState.enabled;
      switch (state) {
        case NotificationPermissionState.enabled:
          return true;
        case NotificationPermissionState.blocked:
          _showMessage('Notifications weren’t enabled.');
        case NotificationPermissionState.unavailable:
          _showMessage('Notifications aren’t available here.');
        case NotificationPermissionState.promptable:
          break;
      }
      return false;
    } on NotificationRegistrationException {
      if (mounted) {
        _showMessage(
          'Permission was granted, but notification setup didn’t finish. '
          'We’ll retry automatically.',
        );
      }
      return false;
    } catch (_) {
      if (mounted) {
        _showMessage('Could not enable notifications. Please try again.');
      }
      return false;
    } finally {
      if (mounted) {
        ref.invalidate(notificationPermissionStatusProvider);
        ref.invalidate(notificationNudgeProvider);
        setState(() => _requesting = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EnableCard extends StatelessWidget {
  const _EnableCard({required this.requesting, required this.onEnable});

  final bool requesting;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notifications_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Don’t miss your turn',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Get an alert when a game is ready, it’s your turn, '
                        'or the result is in.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: requesting ? null : onEnable,
                icon: requesting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_outlined),
                label: const Text('Enable notifications'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenSettingsCard extends StatelessWidget {
  const _OpenSettingsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.notifications_off_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                kIsWeb
                    ? 'Notifications are blocked. Enable them in this site’s '
                          'browser settings so you don’t miss a turn.'
                    : 'Notifications are off. Enable them in Settings so you '
                          'don’t miss a turn.',
              ),
            ),
            if (!kIsWeb) ...[
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => AppSettings.openAppSettings(
                  type: AppSettingsType.notification,
                ),
                child: const Text('Settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
