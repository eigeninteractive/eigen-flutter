import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_flutter/core/analytics/analytics_provider.dart';
import 'package:eigen_flutter/core/errors/error_messages.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';

/// Splash screen shown when the user arrives via a `/join/:code` deep link.
///
/// Immediately fires [joinByCodeProvider] and navigates to [GameScreen] on
/// success, or back to home with a snack bar on failure. The screen is never
/// visible for more than a brief moment.
class JoinGameScreen extends ConsumerWidget {
  const JoinGameScreen({required this.code, super.key});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(joinByCodeProvider(code: code), (_, next) {
      next.whenOrNull(
        data: (joined) {
          unawaited(ref.read(analyticsServiceProvider).joinByCode());
          context.pushReplacementNamed(
            'game',
            pathParameters: {'gameId': joined.gameId},
          );
        },
        error: (e, _) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(humanize(e))));
          context.goNamed('home');
        },
      );
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'Joining game…',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                code,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  letterSpacing: 2,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
