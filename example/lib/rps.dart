/// Rock–Paper–Scissors — the reference game implementation.
///
/// A game package exports its [RpsModule] and its payload types. The module is
/// what `main.dart` hands to `runEngineApp`; the payload types are exported
/// because the game's own tests and bots need to name them.
library;

export 'src/rps_module.dart' show RpsModule;
export 'src/v1/models.dart'
    show RpsAction, RpsConfig, RpsMove, RpsObservation, RpsRound;
export 'src/v1/rules.dart' show RpsRulesV1;
