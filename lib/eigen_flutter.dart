// Dartdoc selects the two supported package entry points by library name.
// ignore_for_file: unnecessary_library_name

/// EigenInteractive: a whitelabel turn-based multiplayer game engine.
///
/// A game app depends on this package, implements a [GameModule], and boots
/// with [runEngineApp]:
///
/// ```dart
/// import 'package:eigen_flutter/eigen_flutter.dart';
///
/// Future<void> main() => runEngineApp(
///   module: const MyGameModule(),
///   config: appConfig,
///   firebaseOptions: firebaseOptions,
///   onBackgroundMessage: onBackgroundMessage,
/// );
/// ```
///
/// This library is the supported app import. It exposes the entry point,
/// composition-root configuration, game contract, wire vocabulary, and shared
/// game UI without exposing the app shell's repositories or transport.
///
/// Start with the
/// [EigenInteractive quickstart](https://eigeninteractive.com/docs/getting-started/quickstart)
/// and use the
/// [task guides](https://eigeninteractive.com/docs/build-a-game/the-contract)
/// for end-to-end TypeScript and Dart examples.
library eigen_flutter;

/// The wire types a game renders from.
///
/// Re-exported deliberately: they are generated, but they *are* this engine's
/// domain vocabulary; there are no hand-written mirrors to hide them behind,
/// and inventing some would be pure transcription. A game app must be able to
/// name a [GameStatus] or an [OutcomeResultEnum] without depending on
/// `eigen_api` itself, which is a build artifact that `tool/generate_api.sh`
/// deletes and rewrites wholesale.
///
/// Listed explicitly rather than exported wholesale so the generated `*Api`
/// classes and their Dio plumbing stay out of an app's namespace: naming a type
/// is part of the contract, calling the server is not.
export 'package:eigen_api/eigen_api.dart'
    show
        Bot,
        ErrorCode,
        Frame,
        Friend,
        FriendRequest,
        GameAccess,
        GameStatus,
        GameSummary,
        Outcome,
        OutcomeResultEnum,
        Player,
        Profile,
        Rating,
        RatingDelta,
        RatingIdentity,
        Roster,
        Seat,
        SeatTypeEnum;

export 'app_runner.dart' show runEngineApp, MyApp;

/// Server time. Exported because [TimingContext.clock] is typed as it, so
/// without this a game could read the field but never name it, which is what
/// building a [GameContentContext] in a widget test requires.
export 'core/api/server_clock.dart' show ServerClock;
export 'core/config/app_config.dart'
    show AppConfig, Branding, EngineConfig, appConfigProvider;
export 'core/errors/engine_exception.dart';
export 'core/game/game_creation_spec.dart';
export 'core/game/game_frame.dart';
export 'core/game/game_module.dart';
export 'core/game/game_player.dart';
export 'core/game/my_seat.dart';
export 'core/game/players_context.dart';
export 'core/game/timing_context.dart';
export 'features/game/providers/game_providers.dart'
    show currentGameModuleProvider;
export 'features/game/presentation/widgets/timer_builders.dart'
    show PlayerTimerBuilder, TurnTimerBuilder;

/// Shared UI a game composes with. Seat rendering in particular belongs here:
/// avatar URLs may be relative to the API host, and routing every avatar
/// through this widget is what keeps that resolution in one place.
export 'shared/widgets/player_avatar.dart' show PlayerAvatar;
export 'shared/widgets/player_tags.dart';
