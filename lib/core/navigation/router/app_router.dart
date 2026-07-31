import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:eigen_flutter/core/navigation/widgets/shell_scaffold.dart';
import 'package:eigen_flutter/features/about/presentation/screens/about_screen.dart';
import 'package:eigen_flutter/features/auth/presentation/screens/login_screen.dart';
import 'package:eigen_flutter/features/game/presentation/screens/game_screen.dart';
import 'package:eigen_flutter/features/game/presentation/screens/history_screen.dart';
import 'package:eigen_flutter/features/game/presentation/screens/join_game_screen.dart';
import 'package:eigen_flutter/features/game/presentation/screens/lobby_screen.dart';
import 'package:eigen_flutter/features/game/presentation/screens/replay_screen.dart';
import 'package:eigen_flutter/features/game/providers/game_providers.dart';
import 'package:eigen_flutter/features/home/presentation/screens/home_screen.dart';
import 'package:eigen_flutter/features/profile/presentation/screens/profile_screen.dart';
import 'package:eigen_flutter/features/settings/presentation/screens/settings_screen.dart';
import 'package:eigen_flutter/features/social/presentation/social_screen.dart';

/// Global navigator key for top-level navigation (e.g., login screen).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// Navigation helpers for notification-triggered routing.
///
/// Routes that use [rootNavigatorKey] (game, join) escape the shell and must
/// be pushed so the system back button returns to wherever the user was.
/// Shell tab routes use [GoRouter.go] to switch tabs without adding a back
/// entry.
extension NotificationNavigation on GoRouter {
  static const _overlayPrefixes = ['/game/', '/join/'];

  /// Navigates to [path] from a notification tap with correct back-stack
  /// semantics: overlay routes are pushed; shell tab routes replace state.
  void navigateFromNotification(String path) {
    if (_overlayPrefixes.any(path.startsWith)) {
      push(path);
    } else {
      go(path);
    }
  }
}

/// App routes configuration using StatefulShellRoute for state preservation
///
/// Routes structure:
/// - /login (standalone, no shell)
/// - /game/:gameId (standalone, no shell, full-screen)
/// - StatefulShellRoute (with drawer, preserves state):
///   - Branch 0: /home
///   - Branch 1: /lobby
///   - Branch 2: /history
///   - Branch 3: /social
///   - Branch 4: /about
///   - Branch 5: /settings
///     - /settings/profile
final List<RouteBase> appRoutes = [
  // The web app is hosted at the game origin. Give its root a real route so a
  // cold load does not depend on the router's exception fallback.
  GoRoute(path: '/', redirect: (context, state) => '/home'),

  // Login route - outside shell (no drawer)
  GoRoute(
    path: '/login',
    name: 'login',
    parentNavigatorKey: rootNavigatorKey,
    builder: (context, state) => const LoginScreen(),
  ),

  // Game route - outside shell (parentNavigatorKey: rootNavigatorKey) so it
  // covers the shell entirely; pushed onto the root navigator so back returns
  // to the source screen (home, lobby, or history).
  GoRoute(
    path: '/game/:gameId',
    name: 'game',
    parentNavigatorKey: rootNavigatorKey,
    onExit: (context, state) async {
      ProviderScope.containerOf(context).invalidate(activeGamesProvider);
      return true;
    },
    builder: (context, state) {
      final gameId = state.pathParameters['gameId']!;
      return GameScreen(gameId: gameId);
    },
    routes: [
      // Replay - full-screen over the game screen (root navigator), so back
      // returns to the finished game. Used both by a participant replaying
      // their own game and by a non-participant replaying a public one.
      GoRoute(
        path: 'replay',
        name: 'replay',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final gameId = state.pathParameters['gameId']!;
          return ReplayScreen(gameId: gameId);
        },
      ),
    ],
  ),

  // Join route - handles deep linking or manual code entry
  GoRoute(
    path: '/join/:code',
    name: 'join',
    parentNavigatorKey: rootNavigatorKey,
    builder: (context, state) {
      final code = state.pathParameters['code']!;
      return JoinGameScreen(code: code);
    },
  ),

  // Stateful shell route - preserves state across branch switches
  StatefulShellRoute.indexedStack(
    parentNavigatorKey: rootNavigatorKey,
    builder: (context, state, navigationShell) {
      // ShellScaffold now receives NavigationShell for built-in navigation
      return ShellScaffold(navigationShell: navigationShell);
    },
    branches: [
      // Branch 0: Home
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (context, state) => const HomeScreen(),
          ),
        ],
      ),

      // Branch 1: Lobby
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/lobby',
            name: 'lobby',
            builder: (context, state) => const LobbyScreen(),
          ),
        ],
      ),

      // Branch 2: History
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/history',
            name: 'history',
            builder: (context, state) => const HistoryScreen(),
          ),
        ],
      ),

      // Branch 3: Social
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/social',
            name: 'social',
            builder: (context, state) => const SocialScreen(),
          ),
        ],
      ),

      // Branch 4: About
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/about',
            name: 'about',
            builder: (context, state) => const AboutScreen(),
          ),
        ],
      ),

      // Branch 5: Settings
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
            routes: [
              // Profile is a full-screen edit flow: it escapes the shell
              // intentionally so the drawer is not accessible while editing.
              GoRoute(
                path: 'profile',
                name: 'profile',
                parentNavigatorKey: rootNavigatorKey,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];
