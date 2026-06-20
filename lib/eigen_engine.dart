/// Eigen Engine — a whitelabel turn-based multiplayer game engine.
///
/// A game app depends on this package, implements a [GameModule] (typically in
/// its own game package), and boots with [runEngineApp]. This barrel exports
/// the public surface a game/app needs: the entry point, the composition-root
/// config, and the game contract.
library;

export 'app_runner.dart' show runEngineApp, MyApp;
export 'core/config/app_config.dart'
    show AppConfig, Branding, EngineConfig, appConfigProvider;
export 'core/game/base_engine.dart';
export 'core/game/local_bot.dart';
export 'core/game/game_creation_spec.dart';
export 'core/game/game_frame.dart';
export 'core/game/game_module.dart';
export 'core/game/game_outcome.dart';
export 'core/game/game_player.dart';
export 'core/game/game_status.dart';
export 'core/game/players_context.dart';
export 'core/game/timing_context.dart';
export 'features/game/providers/game_providers.dart'
    show currentGameModuleProvider;
