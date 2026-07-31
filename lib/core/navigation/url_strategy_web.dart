import 'package:flutter_web_plugins/url_strategy.dart';

/// Keeps browser URLs aligned with the app-link paths served by the game
/// origin (`/join/:code` and `/game/:id`) instead of hiding them after `/#/`.
void configureUrlStrategy() => usePathUrlStrategy();
