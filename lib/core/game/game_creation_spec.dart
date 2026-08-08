/// Infra hard minimum for per-action turn time (seconds).
const kMinTurnSeconds = 30;

/// Infra hard maximum for per-action turn time (30 days).
const kMaxTurnSeconds = 2592000;

/// Infra hard minimum for budget (accumulated) clock (seconds).
const kMinBudgetSeconds = 120;

/// Infra hard maximum for budget (accumulated) clock (10 days).
const kMaxBudgetSeconds = 864000;

/// Configuration for one timing option shown in the new-game dialog.
///
/// Used as map values in [GameCreationSpec.timingConfigs]; the map key
/// becomes the segment label in the dialog. The subtype determines which
/// controls are rendered.
sealed class TimingModeConfig {
  const TimingModeConfig();
}

/// No time limit. Players act at any pace. No additional controls rendered.
class UntimedConfig extends TimingModeConfig {
  const UntimedConfig();
}

/// Each turn gets a fresh fixed window of [minSeconds]–[maxSeconds].
///
/// [minSeconds] is clamped to [kMinTurnSeconds] (30 s), the infra hard
/// limit. The dialog renders a slider between [minSeconds] and [maxSeconds],
/// with optional [presets] shown as quick-pick chips.
class PerActionConfig extends TimingModeConfig {
  const PerActionConfig({
    this.minSeconds = kMinTurnSeconds,
    required this.maxSeconds,
    this.presets = const [],
  }) : assert(
         minSeconds >= kMinTurnSeconds,
         'minSeconds must be ≥ $kMinTurnSeconds (infra hard limit)',
       ),
       assert(maxSeconds > minSeconds, 'maxSeconds must be > minSeconds');

  final int minSeconds;
  final int maxSeconds;

  /// Optional quick-pick values (seconds). Should lie within
  /// [[minSeconds], [maxSeconds]]. Tapping a chip sets the slider.
  final List<int> presets;
}

/// Each player has a personal time bank that drains while they act
/// (Fischer increment).
///
/// [minBudgetSeconds] is clamped to [kMinBudgetSeconds] (120 s). The dialog
/// renders separate bank and increment sliders, with optional [presets]
/// shown as quick-pick chips (each preset sets both sliders simultaneously).
class BudgetConfig extends TimingModeConfig {
  const BudgetConfig({
    this.minBudgetSeconds = kMinBudgetSeconds,
    required this.maxBudgetSeconds,
    this.minIncrementSeconds = 0,
    this.maxIncrementSeconds = 60,
    this.presets = const [],
  }) : assert(
         minBudgetSeconds >= kMinBudgetSeconds,
         'minBudgetSeconds must be ≥ $kMinBudgetSeconds (infra hard limit)',
       ),
       assert(
         maxBudgetSeconds > minBudgetSeconds,
         'maxBudgetSeconds must be > minBudgetSeconds',
       );

  final int minBudgetSeconds;
  final int maxBudgetSeconds;
  final int minIncrementSeconds;
  final int maxIncrementSeconds;

  /// Optional quick-pick pairs. Each record sets both the bank and increment
  /// sliders. Label rendered as "3m+2s" or "10m" when increment is 0.
  final List<({int budget, int increment})> presets;
}

/// Declarative description of what is valid when creating a game of this type.
///
/// Returned by [GameModule.creationSpec]. The engine-owned creation dialog
/// reads this to render only the controls that apply.
class GameCreationSpec {
  const GameCreationSpec({
    required this.minPlayers,
    required this.maxPlayers,
    this.timingConfigs = const {'Untimed': UntimedConfig()},
    this.defaultConfig = const {},
  });

  /// Minimum players required to transition the game to `ready` status.
  final int minPlayers;

  /// Maximum players allowed to join. Must be ≥ [minPlayers].
  final int maxPlayers;

  /// Ordered map of timing options shown in the creation dialog.
  ///
  /// Keys become [SegmentedButton] labels; values declare the valid range and
  /// optional presets for each mode. Insertion order is preserved (Dart
  /// [LinkedHashMap] guarantee), so the first entry is selected by default.
  ///
  /// Multiple entries of the same subtype are allowed: for example, a game
  /// could offer both "Blitz" ([PerActionConfig] 30–300 s) and "Daily"
  /// ([PerActionConfig] 3600–86400 s) as distinct named options.
  final Map<String, TimingModeConfig> timingConfigs;

  /// Initial value for the game-specific config map sent when creating a game.
  ///
  /// Seeded before the player interacts with [GameModule.buildCreationConfig].
  final Map<String, dynamic> defaultConfig;
}
