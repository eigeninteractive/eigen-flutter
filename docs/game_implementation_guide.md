# Game Implementation Guide

This guide explains how to implement a new game using the **Eigen Engine**.

---

## Overview

Eigen Engine is a **whitelabel game engine** — the core infrastructure (auth, networking, real-time updates, timing) is shared, while each game provides its own rules and UI by implementing five SQL hooks (three core — `game_initial_state`, `game_apply_action`, `game_compute_observation`; two optional — `game_rating_pool`, `game_handle_system_action`) and one Dart `GameModule`.

### Project setup

Your game is a Flutter **app** that depends on `eigen_engine`. Until the engine
is published to pub.dev, clone it as a **sibling** of your app and depend on it
by **path**:

```yaml
dependencies:
  eigen_engine:
    path: ../eigen_engine
```

The engine's generated code is not committed, so generate it once after cloning
(and again in CI before building your app):

```bash
cd eigen_engine && flutter pub get && dart run build_runner build
```

The same path setup is used in local and CI — CI checks out the engine beside
the app (private repo: via an SSH deploy key) and generates its code first. See
[`versioning.md`](versioning.md) for the full dependency + release model.

**Fonts.** Nothing to do per app. The engine **bundles Inter as a package font**
(all 9 weights, declared under `fonts:` in the engine `pubspec.yaml`), so Flutter
includes it in every consuming app automatically and it **renders offline from
the first frame** — no `google_fonts`, no runtime fetch, no per-app asset wiring.
The theme references it as `packages/eigen_engine/Inter`. To change the typeface,
add the new family's weights to the engine's `fonts/` + `pubspec.yaml` and update
that one constant in `AppTheme`. (Engine maintainers regenerate the Inter weights
with `tool/download_fonts.sh`.)

**Recommended structure.** A single Flutter app with the game under a
`lib/game/` folder. The game ↔ engine boundary is already compiler-enforced
(the engine is a separate package), so a folder is enough; you don't need a
separate game package:

```
my_app/                           # a standard Flutter app (this is the repo root)
├── pubspec.yaml                  # depends on eigen_engine
├── lib/
│   ├── main.dart                 # runEngineApp(module: const MyGameModule(), …)
│   ├── env/                      # envied env config
│   └── game/                     # the game (no Firebase/secrets/platform here)
│       ├── data/models/game_models.dart  # ObservationData, ActionData, GameConfigData (Freezed)
│       ├── logic/my_game_engine.dart      # BaseEngine implementation
│       ├── presentation/{my_game_board,my_game_content}.dart
│       └── game_module.dart      # the GameModule
└── supabase/                     # config + migrations (engine vendored + your game hook)
```

Engine contracts are imported from `package:eigen_engine/...` (or the
`package:eigen_engine/eigen_engine.dart` barrel); game files import each other
via `package:my_app/game/...`.

> *Optional (advanced):* if you ever need to share one game across multiple apps
> or test it in isolation, extract `lib/game/` into its own package and make the
> app a small pub workspace (`packages/my_game` + `apps/my_app`). Not needed for
> a one-game-per-app product.

---

## Checklist for a New Game

### 1. Data Models (`data/models/game_models.dart`)

Create Freezed models for your game's observation, action, and config:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'game_models.freezed.dart';
part 'game_models.g.dart';

/// Observation data received from the server — pure game-specific payload.
/// Turn/winner info lives on the infra-level Observation row and Game row;
/// do NOT duplicate it here.
@freezed
abstract class ObservationData with _$ObservationData {
  const factory ObservationData({
    required List<int> board,
    required int actionCount,
  }) = _ObservationData;

  factory ObservationData.fromJson(Map<String, dynamic> json) =>
      _$ObservationDataFromJson(json);
}

/// Action data sent to the server.
@freezed
abstract class ActionData with _$ActionData {
  const factory ActionData({
    required int position,
  }) = _ActionData;

  factory ActionData.fromJson(Map<String, dynamic> json) =>
      _$ActionDataFromJson(json);
}

/// Per-instance game configuration from the database.
///
/// Infra passes this through to the three game hooks unchanged.
/// Put game-specific settings here (board size, variant flags, etc.).
/// Do NOT put timing here — timing lives in games.turn_seconds /
/// budget_seconds / increment_seconds (infra columns).
@freezed
abstract class GameConfigData with _$GameConfigData {
  const factory GameConfigData({
    int? boardSize,
  }) = _GameConfigData;

  factory GameConfigData.fromJson(Map<String, dynamic> json) =>
      _$GameConfigDataFromJson(json);
}
```

> **Note:** `Observation.data` in the core layer is `Map<String, dynamic>`. Your content widget receives this already deserialized into `ObservationData` at the game layer boundary (see step 5).

> **Evolving these models after launch.** Once real users have games in
> progress, these three payloads become a compatibility contract. Make new
> fields nullable or `@Default(...)` and give enums
> `@JsonKey(unknownEnumValue: …)`; a change that alters a field's meaning or the
> board/action shape is breaking and needs a `schema` bump on the game type, not
> an in-place edit. See [`backward-compatibility.md`](backward-compatibility.md).

---

### 2. Game Engine (`logic/`)

`BaseEngine` is intentionally minimal. It is responsible only for:

- `config` — the per-instance game configuration.
- `isValidAction` — local legality check for UX feedback only. Authoritative validation happens server-side in `game_apply_action`.
- Pure rendering helpers (e.g., "which cells form the winning line" for highlight rendering).

Player counts are declared on `GameCreationSpec`, and player identities arrive
via `PlayersContext` — the engine carries no player metadata.

Turn-gating, game-over detection, and winner derivation are **infra-level facts**, surfaced via `observations.pending_players`, `games.status`, and `game_outcomes`. The engine never re-derives them.

```dart
import 'package:eigen_engine/core/game/base_engine.dart';
import 'package:my_game/data/models/game_models.dart';

class MyGameEngine
    extends BaseEngine<ObservationData, ActionData, GameConfigData> {
  MyGameEngine(super.config);

  @override
  ObservationData parseObservation(Map<String, dynamic> json) =>
      ObservationData.fromJson(json);

  @override
  bool isValidAction(
    ObservationData obs,
    List<int> pendingPlayers,
    ActionData action,
    int playerIndex,
  ) {
    // Boundary / empty-cell / rule-specific legality.
    // Do NOT re-check whose turn it is for the sequential case —
    // the caller already gated on pendingPlayers.contains(myPlayerIndex).
    return true;
  }
}
```

#### `isValidAction` parameters across game styles

All four parameters are passed on every call so the contract stays uniform. Your engine ignores whatever it doesn't need.

| Game | `obs` | `pendingPlayers` | `action` | `playerIndex` |
|---|---|---|---|---|
| **TicTacToe** (sequential, no ownership) | board | ignored | target cell | ignored |
| **Chess** (sequential, piece ownership) | board | ignored | from/to squares | used — "is that my color?" |
| **Set** (any-player, race) | face-up cards | used — "am I still eligible?" | the set of 3 | ignored |
| **Rock-Paper-Scissors** (simultaneous) | who has submitted | used — "am I still pending?" | my choice | used — only update my slot |
| **Exploding Kittens** (sequential + interrupts) | hand, discard, deck top | used — main-turn vs. Nope interrupt | the card | used — "do I hold this?" |

Concrete examples:
- **Chess** — read `action.from`, look up the piece on `obs.board`, return false unless the piece color matches `playerIndex`.
- **Exploding Kittens** — if `action.card == Nope`, only check that `obs.hand[playerIndex]` contains a Nope (anyone may Nope, even if not in `pendingPlayers`). Otherwise, require `pendingPlayers.contains(playerIndex)` and that the played card is in hand.

---

### 3. Board Widget (`presentation/my_game_board.dart`)

Stateless widget that renders the game board and emits tap events:

```dart
class MyGameBoard extends StatelessWidget {
  const MyGameBoard({
    super.key,
    required this.board,
    required this.enabled,
    required this.onCellTap,
  });

  final List<int> board;
  final bool enabled;
  final void Function(int position) onCellTap;

  @override
  Widget build(BuildContext context) {
    // Render your game board.
  }
}
```

---

### 4. Game Module (`game_module.dart`)

The module is the single file that wires everything together and registers the game with the engine. It implements `GameModule` from `core/game/game_module.dart`.

```dart
import 'package:flutter/material.dart';
import 'package:eigen_engine/core/game/game_creation_spec.dart';
import 'package:eigen_engine/core/game/game_module.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/core/game/game_status.dart';
import 'package:eigen_engine/core/game/timing_context.dart';
import 'package:my_game/data/models/game_models.dart';
import 'package:my_game/logic/my_game_engine.dart';
import 'package:my_game/presentation/my_game_content.dart';

class MyGameModule extends GameModule {
  const MyGameModule();

  @override
  GameCreationSpec get creationSpec => const GameCreationSpec(
    minPlayers: 2,
    maxPlayers: 2,
    // Keys become SegmentedButton labels; values declare the range and
    // optional quick-pick presets. Insertion order is preserved.
    // Budget mode must only be included for strictly sequential games.
    timingConfigs: {
      'Untimed': UntimedConfig(),
      'Rapid': PerActionConfig(
        minSeconds: 60,
        maxSeconds: 600,
        presets: [60, 120, 300, 600],
      ),
      'Daily': PerActionConfig(
        minSeconds: 3600,
        maxSeconds: 86400,
        presets: [3600, 14400, 86400],
      ),
    },
  );

  @override
  Widget? buildCreationConfig({
    required ValueChanged<Map<String, dynamic>> onChanged,
  }) => null; // Return a widget here if players configure game-specific options
              // at creation time (board size, starting chips, variant rules…).
              // Call onChanged whenever the selection changes; the dialog
              // collects the latest value at submit without triggering rebuilds.

  @override
  MyGameEngine createEngine(Map<String, dynamic> configJson) =>
      MyGameEngine(GameConfigData.fromJson(configJson));

  @override
  Widget buildContent(GameContentContext context) =>
      MyGameContent(content: context);
}
```

`buildContent` takes a single [`GameContentContext`](../lib/core/game/game_module.dart) and your content widget consumes it directly (`MyGameContent(content: context)`) rather than re-declaring and unpacking each field — so adding new infra data later never changes the signature or forces every game to update. The context exposes the two halves of the live game as separate members — `engine` (created once from config, long-lived) and `frame` (the per-event observation snapshot: `frame.observation`, `frame.pendingPlayers`, `frame.version`, `frame.timing`) — plus `gameStatus`, `outcomes`, `actionPending`, `onAction`, `onInvalidAction`, `playersContext`, and the convenience getters `myPlayerIndex` (delegates to `playersContext.myPlayerIndex`) and `timing` (delegates to `frame.timing`).

Register the module — and the app's branding + runtime config — in the app's
`main.dart` (`apps/<my_app>/lib/main.dart`) by calling `runEngineApp`. It
installs the `currentGameModuleProvider` and `appConfigProvider` overrides for
you:

```dart
import 'package:eigen_engine/eigen_engine.dart';
import 'package:my_game/my_game.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage m) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() => runEngineApp(
  module: const MyGameModule(),
  firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  onBackgroundMessage: _bgHandler,
  config: AppConfig(
    branding: const Branding(appName: 'My Game', seedColor: Colors.indigo),
    engine: EngineConfig(
      supabaseUrl: Env.supabaseUrl,
      supabasePublishableKey: Env.supabasePublishableKey,
      googleWebClientId: Env.googleWebClientId,
      firebaseVapidKey: Env.firebaseVapidKey,
      appHost: Env.appHost,
      legalHost: Env.legalHost,
    ),
  ),
);
```

#### `GameCreationSpec` reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `minPlayers` | `int` | required | Minimum players to transition game to `ready`. |
| `maxPlayers` | `int` | required | Maximum players allowed to join. Must be ≥ `minPlayers`. |
| `timingConfigs` | `Map<String, TimingModeConfig>` | `{'Untimed': UntimedConfig()}` | Ordered map of timing options. Keys become `SegmentedButton` labels; insertion order is the display order. |
| `defaultConfig` | `Map<String, dynamic>` | `{}` | Seed value for the config map when `buildCreationConfig` is null. |

#### Timing config types

| Type | Controls rendered | Key fields | Infra constraint |
|------|-------------------|------------|-----------------|
| `UntimedConfig()` | None | — | — |
| `PerActionConfig(min, max, presets)` | Preset chips + slider | `minSeconds` ≥ 30, `maxSeconds` > min | `turn_seconds` ≥ 30 |
| `BudgetConfig(minBudget, maxBudget, minInc, maxInc, presets)` | Bank slider + increment slider + preset chips | `minBudgetSeconds` ≥ 120 | `budget_seconds` ≥ 120 |

Multiple entries of the same subtype are allowed — a game can offer both a `'Blitz'` and a `'Daily'` `PerActionConfig` as distinct named segments. `BudgetConfig` must only appear in games where at most one player is pending at a time (see `engine_architecture.md §3`).

#### Variable player counts

`minPlayers` and `maxPlayers` can differ to support lobbies that start with a range of player counts (e.g. `min: 2, max: 6` for a party game). `join_game` accepts participants until `max_players` is reached. The game transitions to `ready` when the count hits `min_players` and the host can start at any point from there.

Override `playersForConfig` when the valid range depends on a config choice made at creation time:

```dart
@override
(int min, int max) playersForConfig(Map<String, dynamic> config) {
  final count = config['player_count'] as int? ?? 4;
  return (count, count); // fixed size chosen by the host
}
```

#### `buildCreationConfig` example (game with options)

For a game like Go where the player picks board size at creation:

```dart
@override
Widget? buildCreationConfig({
  required ValueChanged<Map<String, dynamic>> onChanged,
}) =>
    _BoardSizePicker(onChanged: onChanged);

class _BoardSizePicker extends StatefulWidget {
  const _BoardSizePicker({required this.onChanged});
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_BoardSizePicker> createState() => _BoardSizePickerState();
}

class _BoardSizePickerState extends State<_BoardSizePicker> {
  int _size = 19;

  @override
  Widget build(BuildContext context) =>
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 9, label: Text('9×9')),
          ButtonSegment(value: 13, label: Text('13×13')),
          ButtonSegment(value: 19, label: Text('19×19')),
        ],
        selected: {_size},
        onSelectionChanged: (selection) {
          setState(() => _size = selection.first);
          widget.onChanged({'board_size': _size});
        },
      );
}
```

The widget manages its own visual state. The dialog captures the latest value via `onChanged` into a plain field (no `setState`) and passes it to `create_game` at submit.

---

### 5. Content Widget (`presentation/my_game_content.dart`)

Receives pre-parsed, typed data. No JSON parsing or engine construction here — both happen once per network event in the session provider.

```dart
import 'package:flutter/material.dart';
import 'package:eigen_engine/core/game/game_module.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/core/game/game_status.dart';
import 'package:my_game/data/models/game_models.dart';
import 'package:my_game/logic/my_game_engine.dart';
import 'package:my_game/presentation/my_game_board.dart';

class MyGameContent extends StatelessWidget {
  const MyGameContent({super.key, required this.content});

  /// The infra-provided context: typed engine, current observation frame,
  /// player identities, outcomes and action callbacks. Pull what you need off
  /// it in `build` — adding new infra data never changes this widget's
  /// constructor.
  final GameContentContext content;

  @override
  Widget build(BuildContext context) {
    // Pull the typed locals your content needs off the context. Cast the
    // engine and observation to your concrete types — the cast is sound by
    // construction: the same module's createEngine()/parseObservation()
    // produced them.
    final engine = content.engine as MyGameEngine;
    final observation = content.frame.observation as ObservationData;
    final pendingPlayers = content.frame.pendingPlayers;
    final gameStatus = content.gameStatus;
    final myPlayerIndex = content.myPlayerIndex;
    final outcomes = content.outcomes;
    final actionPending = content.actionPending;
    // Also available: content.timing (clocks), content.playersContext (names).

    final isMyTurn = pendingPlayers.contains(myPlayerIndex);
    final isGameOver = gameStatus == GameStatus.finished;
    final didIWin = outcomes.any(
      (o) => o.playerIndex == myPlayerIndex && o.result == OutcomeResult.win,
    );
    final isDraw =
        isGameOver && !outcomes.any((o) => o.result == OutcomeResult.win);
    final canPlay = gameStatus == GameStatus.active && isMyTurn && !actionPending;

    return MyGameBoard(
      board: observation.board,
      enabled: canPlay,
      onCellTap: (position) {
        final action = ActionData(position: position);
        if (engine.isValidAction(observation, pendingPlayers, action, myPlayerIndex)) {
          // Infra wires onInvalidAction to HapticFeedback.selectionClick() —
          // do not import flutter/services or choose the haptic yourself.
          content.onAction(action.toJson());
        } else {
          content.onInvalidAction();
        }
      },
    );
  }
}
```

---

## Player Identity

The infra layer resolves all player identities before calling `buildContent()`. The game implementor receives a `PlayersContext` with guaranteed non-nullable data — no null checks, no loading states, no provider watches needed.

For finished games where a participant's account has since been deleted, infra provides a **synthetic identity** (`displayName: 'Deleted User'`, `username: 'player_$index'`) so the seat is always populated. Check `player.isDeleted` before calling `PlayerProfileSheet.show` — the synthetic identity has no real database record to look up.

> **Game identity vs social identity:** `PlayerInfo` and `playerInfoCacheProvider` cover both humans and bots — they are the right tool inside game screens, lobby cards, and anywhere a game seat needs a name/avatar. Social features (friend search, friend requests) are human-only and never surface bots. Game code should not check player type to decide whether to display identity — treat all `GamePlayer` entries uniformly; use `GamePlayer.type` only when game rules need to distinguish (e.g. "is this a bot seat I should auto-play?").

### Accessing Player Data

```dart
final playersContext = content.playersContext;

// Get a specific player by index
final opponent = playersContext[1];
opponent.info.username;    // "seenu_k" (always present)
opponent.info.avatarUrl;   // "https://..." or null
opponent.type;            // ParticipantType.human

// Get the current user
final me = playersContext.me;
me.info.username;          // your username
me.playerIndex;            // your seat index (same as myPlayerIndex)

// Iterate all players
for (final gp in playersContext.players.values) {
  print('Player ${gp.playerIndex}: @${gp.info.username}');
}
```

### `GamePlayer` Fields

| Field | Type | Description |
|-------|------|-------------|
| `playerIndex` | `int` | 0-based seat in the game |
| `type` | `ParticipantType` | The type of this player (human, bot) |
| `info` | `PlayerInfo` | Resolved identity (username, displayName, avatarUrl) |
| `isDeleted` | `bool` | True when the account no longer exists. `info` is a synthetic placeholder — do not pass `info.id` to identity lookups or `PlayerProfileSheet`. |

> Per-game **roles** (host/guest, team, faction, dealer…) are *not* an infra concept — they live in your game's observation/state JSON, where your engine and `game_compute_observation` hook can shape them freely. Infra only tracks the seat index (`playerIndex`) and `type`.

### `PlayersContext` API

| Member | Type | Description |
|--------|------|-------------|
| `players` | `Map<int, GamePlayer>` | All players keyed by index |
| `myPlayerIndex` | `int` | Current user's seat (-1 if spectating) |
| `operator [](int)` | `GamePlayer` | Non-nullable access by index |
| `me` | `GamePlayer` | Convenience for `this[myPlayerIndex]` |

### Displaying Avatars

Use `PlayerAvatar` with a `GamePlayer`'s identity:

```dart
import 'package:eigen_engine/features/social/presentation/widgets/player_profile_sheet.dart';
import 'package:eigen_engine/shared/widgets/player_avatar.dart';

final player0 = playersContext[0];
PlayerAvatar(
  playerInfo: player0.info,
  radius: 24,
  showBorder: pendingPlayers.contains(0),  // highlight active player
  borderColor: colorScheme.primary,
  onTap: player0.isDeleted
      ? null
      : () => PlayerProfileSheet.show(
            context,
            playerId: player0.info.id,
            type: player0.type,
          ),
)
```

`PlayerAvatar` handles:
- Network image loading with `cached_network_image`
- Person-icon placeholder when loading or if `avatarUrl` is null/invalid
- Optional border for active/highlighted state
- `onTap` is optional — when `null` the avatar is non-interactive. Pass a callback to open `PlayerProfileSheet`; guard deleted players with `player.isDeleted` so the synthetic identity is never passed to identity lookups.

### Complete Player Indicator Example (TicTacToe)

```dart
class _PlayerIndicator extends StatelessWidget {
  const _PlayerIndicator({
    required this.isActive,
    required this.isMe,
    required this.color,
    required this.player,
  });

  final bool isActive;
  final bool isMe;
  final Color color;
  final GamePlayer player;  // non-nullable, guaranteed by infra

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerAvatar(
          playerInfo: player.info,
          radius: 24,
          showBorder: isActive,
          borderColor: color,
          onTap: player.isDeleted
              ? null
              : () => PlayerProfileSheet.show(
                    context,
                    playerId: player.info.id,
                    type: player.type,
                  ),
        ),
        const SizedBox(height: 4),
        Text(
          isMe ? 'You' : '@${player.info.username}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
```

### Data Availability Guarantee

The game screen only calls `buildContent()` after `gamePlayersProvider(gameId)` has fully resolved. This means:
- `playersContext[i]` never returns null — it's typed as `GamePlayer`, not `GamePlayer?`
- No `AsyncValue` handling needed in game content widgets
- No shimmer/loading fallbacks required for player identity
- If identity data is still loading, the game screen shows its own loading indicator before your widget is ever constructed
- **Deleted accounts:** for finished games where a participant later deleted their account, infra returns a synthetic identity (`displayName: 'Deleted User'`, `username: 'player_$playerIndex'`). The seat is always populated, but `PlayerProfileSheet.show` must not be called — guard with `player.isDeleted`.

---

## Timing Widgets

By default the game screen shows an infra-owned timing header above your content widget:
- **Per-action mode** — `TurnCountdown`: a single shared "12m 34s" / "45s" countdown, error-red under 60 s.
- **Budget mode** — `BudgetClock`: a row of per-player "M:SS" cells, the active player's draining live.
- **Untimed** — nothing shown.

Most games need no extra work. If your game needs custom clock placement (e.g. Chess showing each player's clock next to their captured pieces, or a 6-player game only showing the active player's clock), use the headless builder widgets directly.

> The fragments below assume you've pulled locals off the context in `build`, as in the content-widget template: `final timing = content.timing;`, `final pendingPlayers = content.frame.pendingPlayers;`, `final myPlayerIndex = content.myPlayerIndex;`.

### `TurnTimerBuilder` — per-action countdown

Owns a `Timer.periodic(1 s)`, ticks toward `deadline`, self-cancels at zero. Passes the remaining `Duration` to your `builder` callback.

Pass `isPaused: true` to freeze the displayed value without cancelling the timer — it resumes from the correct wall-clock position when `isPaused` returns to `false`. Use this to stop the clock from visually counting down while the device is offline. The infra-owned `TurnCountdown` shell does this automatically; you must wire it yourself when using the headless builder.

Because `isOfflineProvider` is a Riverpod provider, your content widget must extend `ConsumerWidget` (not `StatelessWidget`) to read it:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_engine/core/connectivity/connectivity_provider.dart';
import 'package:eigen_engine/features/game/presentation/widgets/timer_builders.dart';

// Content widget must be ConsumerWidget to watch isOfflineProvider.
TurnTimerBuilder(
  deadline: timing.turnDeadline!,
  isPaused: ref.watch(isOfflineProvider),
  builder: (context, remaining) {
    if (remaining == Duration.zero) return const SizedBox.shrink();
    final s = remaining.inSeconds;
    return Text('$s s', style: TextStyle(color: s < 60 ? Colors.red : null));
  },
)
```

### `PlayerTimerBuilder` — one player's budget clock

Owns a `Timer.periodic(1 s)`. For the active player it drains live using `turnStartedAt`; for inactive players it shows the static bank value. Passes `(int remainingMs, bool isActive)` to your `builder` callback.

`playerTimes` is 0-indexed by player index — the same scheme as `pendingPlayers`. `playerTimes[myPlayerIndex]` is your bank; `playerTimes[i]` is any player's bank.

Pass `isPaused: ref.watch(isOfflineProvider)` for the same reason as `TurnTimerBuilder` — otherwise the bank appears to drain while the device is offline. The infra-owned `BudgetClock` shell does this automatically.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eigen_engine/core/connectivity/connectivity_provider.dart';
import 'package:eigen_engine/features/game/presentation/widgets/timer_builders.dart';

// Show your own clock only
PlayerTimerBuilder(
  playerTimes: timing.playerTimes!,
  turnStartedAt: timing.turnStartedAt,
  pendingPlayers: pendingPlayers,
  playerIndex: myPlayerIndex,
  isPaused: ref.watch(isOfflineProvider),
  builder: (context, remainingMs, isActive) {
    final s = remainingMs ~/ 1000;
    final label = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return MyClockCell(label: label, active: isActive);
  },
)

// Show only the active player's clock (useful for large N-player games)
if (timing.playerTimes != null && pendingPlayers.isNotEmpty)
  PlayerTimerBuilder(
    playerTimes: timing.playerTimes!,
    turnStartedAt: timing.turnStartedAt,
    pendingPlayers: pendingPlayers,
    playerIndex: pendingPlayers.first,
    isPaused: ref.watch(isOfflineProvider),
    builder: (context, remainingMs, isActive) =>
        ActivePlayerClock(ms: remainingMs),
  )

// Show all players' clocks (e.g. Chess)
for (int i = 0; i < timing.playerTimes!.length; i++)
  PlayerTimerBuilder(
    playerTimes: timing.playerTimes!,
    turnStartedAt: timing.turnStartedAt,
    pendingPlayers: pendingPlayers,
    playerIndex: i,
    isPaused: ref.watch(isOfflineProvider),
    builder: (context, remainingMs, isActive) =>
        ChessClockCell(ms: remainingMs, active: isActive, isMe: i == myPlayerIndex),
  )
```

When you provide custom timing display inside your content widget, the infra header above the board is still visible. If you want to suppress it, that is a future concern — for now, avoid duplicating the same clock in both places by not watching the infra header's timing mode condition.

---

## Database Changes Required

Replacing **five SQL functions** produces a completely different game. All infra RPC functions stay untouched.

Write your hooks as a normal, committed migration in your app's
`supabase/migrations/YYYYMMDD_my_game.sql`. The engine's **backend** is
**vendored** in alongside it — run `dart run eigen_engine:sync_supabase` from
the app directory. It copies the engine's `migrations/*.sql`, edge `functions/`
(`update-ratings`, `refresh-fcm-token`), and `seed.sql` into your `supabase/`,
leaving your app-owned files (your game migration, any app-specific functions)
untouched. Commit everything, then `supabase db reset`. Re-run when you bump the
engine version. See **Supabase project setup** below for the one-time config.

Because Postgres does not resolve plpgsql function references at `CREATE` time,
your migration may either define the hooks early (before the infra-functions
migration) or **override** the defaults with a later-timestamped
`CREATE OR REPLACE`.

Once your app is in production, migrations become append-only and schema changes
must stay backward-compatible with app versions still in the wild — see
[`versioning.md`](versioning.md) (expand/contract, mobile update lag, in-flight
game state).

### Supabase project setup (one-time, per app)

The engine vendors the *content* of the backend (migrations, functions, seed),
but each app owns its Supabase **project config**:

1. **`config.toml`** — `supabase init` generates a default; base yours on the
   **engine's `supabase/config.toml`** (it's the reference) and set your own
   `project_id`. Ensure the engine-required settings are present:
   - `[db.seed] sql_paths = ["./seed.sql"]`
   - `[auth] signing_keys_path = "./signing_keys.json"`,
     `[auth.external.google]` (`client_id`/`secret` from env), and
     `enable_anonymous_sign_ins` as desired
   - `[edge_runtime]` + `[functions.update-ratings]` / `[functions.refresh-fcm-token]`
     (`verify_jwt = false`, `import_map` / `entrypoint` pointing at each function)
2. **Vendor the backend:** `dart run eigen_engine:sync_supabase` (migrations +
   functions + seed), then commit.
3. **`functions/.env.local`** — copy the engine's `functions/.env.local.example`
   and fill in `SERVERLESS_SECRET` + the Firebase service-account vars
   (`FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`, `FIREBASE_PROJECT_ID`). This
   file is git-ignored.
4. **`signing_keys.json`** — local JWT signing keys; git-ignored and created by
   the Supabase CLI for local dev (see Supabase local-development docs). Not
   vendored.
5. `supabase start` → `supabase db reset` (applies migrations + `seed.sql`).
6. **Production:** deploy the edge functions and set their secrets — see the
   *Backend / Supabase Production Checklist* near the end of this guide.

---

### Hook 0: `game_rating_pool(p_access, p_turn_seconds, p_budget_seconds, p_increment_seconds, p_min_players, p_max_players, p_config)` → TEXT

Called by `create_game` to derive the rating pool name from the game's configuration. Returns `NULL` to mark the game as unrated; returns a pool name string (e.g. `'rapid'`, `'daily'`) to make it ratable.

The client passes a `rated_preference BOOLEAN` — if the user wants a rated game. `create_game` calls this hook; if it returns `NULL`, the game is forced unrated regardless of the client preference. The client can never forge a pool name.

**Default implementation** (in `private.game_implementation_functions`): returns `NULL` for all configurations (all games unrated until overridden).

```sql
CREATE OR REPLACE FUNCTION private.game_rating_pool(
  p_access            public.game_access,
  p_turn_seconds      INT,
  p_budget_seconds    INT,
  p_increment_seconds INT,
  p_min_players       INT,
  p_max_players       INT,
  p_config            JSONB
)
RETURNS TEXT AS $$
BEGIN
  -- Only public games can be rated.
  IF p_access != 'public' THEN RETURN NULL; END IF;

  -- Map timing mode to pool name.
  IF p_turn_seconds   IS NOT NULL THEN RETURN 'rapid'; END IF;
  IF p_budget_seconds IS NOT NULL THEN RETURN 'daily'; END IF;

  -- Untimed public games are unrated.
  RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE SET search_path = '';
```

**The rated toggle in the New Game dialog** is always shown regardless of game type. On submit:
1. If the user toggled off → game is created unrated immediately (no RPC call to pool function).
2. If the user toggled on → `create_game` is called with `p_rated_preference = true`. The server calls `game_rating_pool()`; if it returns `NULL` the game is forced unrated, otherwise the game is rated with that pool.

The game implementor does not need to expose or validate pool names in Dart — that is fully server-owned.

---

### Hook 1: `game_initial_state(p_seed, p_config, p_player_count)` → envelope

Returns the starting envelope. Must include `state`, `pending_players`, and `rng_seed`. May include `turn_seconds`.

```sql
CREATE OR REPLACE FUNCTION private.game_initial_state(
  p_seed         BIGINT,
  p_config       JSONB,
  p_player_count INT
)
RETURNS JSONB AS $$
DECLARE
  r RECORD;
BEGIN
  -- Consume randomness via prng_next if your setup needs it (shuffle, deal, etc.).
  -- SELECT * INTO r FROM private.prng_next(p_seed);
  -- p_seed := r.next_seed;

  RETURN jsonb_build_object(
    'state', jsonb_build_object(
      'board', '[]'::jsonb,
      'action_count', 0
    ),
    'pending_players', jsonb_build_array(0),
    'rng_seed', p_seed   -- return the (possibly advanced) seed
    -- 'turn_seconds', 60  -- optional: override timing for the very first action only
  );
END;
$$ LANGUAGE plpgsql STABLE SET search_path = '';
```

**Return envelope fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `state` | yes | Pure game payload. No whose-turn or winner info. |
| `pending_players` | yes | 0-based indices that may act first. |
| `rng_seed` | yes | The seed after consuming any setup randomness. **Must be non-zero** — infra raises if null or 0. |
| `turn_seconds` | no | Fixed deadline for the first action only (overrides game-level timing for this action). Omit to use the game's configured timing mode. |

---

### Hook 2: `game_apply_action(p_state, p_pending, p_data, p_player_index, p_rng_seed, p_config)` → envelope

Called by `submit_action` for player-initiated actions only. Returns the updated state envelope.

```sql
CREATE OR REPLACE FUNCTION private.game_apply_action(
  p_current_state   JSONB,
  p_pending_players INT[],
  p_data            JSONB,
  p_player_index    INT,
  p_rng_seed        BIGINT,
  p_config          JSONB
)
RETURNS JSONB AS $$
DECLARE
  v_new_state   JSONB;
  v_new_pending INT[];
  v_outcome     JSONB;   -- null = ongoing; array = game over
  v_seed        BIGINT := p_rng_seed;
  r             RECORD;
BEGIN
  -- 1. Validate the action is legal (boundary check, hand contents, etc.).
  -- 2. Apply the action to produce the new state.
  -- 3. Consume randomness as needed: SELECT * INTO r FROM private.prng_next(v_seed);
  --    v_seed := r.next_seed;
  -- 4. Check for win/draw; set pending_players (empty on game over).

  RETURN jsonb_build_object(
    'state',           v_new_state,
    'pending_players', v_new_pending,
    'rng_seed',        v_seed
  ) || CASE
    WHEN v_outcome IS NOT NULL
    THEN jsonb_build_object('outcome', v_outcome)
    ELSE '{}'::jsonb
  END;
END;
$$ LANGUAGE plpgsql SET search_path = '';
```

**Return envelope fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `state` | yes | Updated game payload. |
| `pending_players` | yes | Who acts next. Empty array = game over. |
| `rng_seed` | yes | The seed after consuming any randomness. **Must be non-zero.** |
| `outcome` | no | **Omit when the game is ongoing** — an absent key is how infra knows play continues. Include on game end as an array of per-player results (see below). |
| `turn_seconds` | no | Fixed deadline for **this action only** — does not touch any player's budget bank. Use for phase-specific windows (Nope window, betting timer). Omit to let infra apply the game's configured timing mode. |

**`outcome` array format** (one entry per participant):

```json
[
  { "player_index": 0, "result": "win",  "placement": 1, "team_index": 0 },
  { "player_index": 1, "result": "loss", "placement": 2, "team_index": 1 }
]
```

Required keys: `player_index` (int), `result` (`"win"` | `"loss"` | `"draw"` | `"eliminated"`), `placement` (int, 1 = best, ties share the same value), `team_index` (int, use `player_index` for individual games; teammates share a value for team games). Optional: `"score"` (numeric). See `engine_architecture.md §8` for team game and N-player examples.

**Mid-game player elimination** (Poker bust-out, Exploding Kittens explosion): `game_outcomes` is only written once, when the game ends. Do not include eliminated players in the `outcome` array until the game is truly over. Instead:

- Exclude eliminated players from all future `pending_players` returns.
- Record the elimination in `p_current_state` (e.g. `{"eliminated": [2], "placement": {"2": 4}}`).
- In `game_compute_observation`, put `{"is_eliminated": true, "placement": 4}` in the eliminated player's observation slice — the content widget uses this to show "You were eliminated" immediately.
- When the game ends, build the full `outcome` array including eliminated players with their correct `"placement"` values for ELO.

---

### Hook 2b: `game_handle_system_action(p_state, p_pending, p_action_type, p_data, p_rng_seed, p_config)` → envelope

Called by infra for **all system-initiated events**: timeouts, forfeits, auto-forfeits. This is the only system hook — adding new event types never requires a new function signature, just a new `WHEN` branch.

**Known `p_action_type` values and their `p_data` fields:**

| Value | Trigger | `p_data` fields |
|-------|---------|-----------------|
| `'timeout'` | `expire_turn` (cron or `trigger_turn_expiry` client nudge) | `player_index` |
| `'forfeit'` | `forfeit_game` RPC | `player_index` |
| `'auto_forfeit'` | Idle-cleanup cron (future) | `player_index` |

```sql
CREATE OR REPLACE FUNCTION private.game_handle_system_action(
  p_state       JSONB,
  p_pending     INT[],
  p_action_type system_action_type,
  p_data        JSONB,
  p_rng_seed    BIGINT,
  p_config      JSONB
)
RETURNS JSONB AS $$
DECLARE
  v_player_index INT;
  v_winner       INT;
BEGIN
  CASE p_action_type
    WHEN 'timeout', 'forfeit', 'auto_forfeit' THEN
      v_player_index := (p_data->>'player_index')::INT;
      v_winner       := (v_player_index + 1) % 2; -- adjust for N>2 games
      RETURN jsonb_build_object(
        'state',           p_state,
        'pending_players', '[]'::jsonb,
        'outcome', jsonb_build_array(
          jsonb_build_object('player_index', v_winner,       'result', 'win',  'placement', 1, 'team_index', v_winner),
          jsonb_build_object('player_index', v_player_index, 'result', 'loss', 'placement', 2, 'team_index', v_player_index)
        ),
        'rng_seed', p_rng_seed
      );
    ELSE
      RAISE EXCEPTION 'Unhandled system action type: %', p_action_type;
  END CASE;
END;
$$ LANGUAGE plpgsql SET search_path = '';
```

**Return envelope:** identical to `game_apply_action` — `state`, `pending_players`, `rng_seed`, optional `outcome` (omit when ongoing), optional `turn_seconds`.

**Common patterns:**

```sql
-- Forfeit/lose: affected player loses immediately (chess, TicTacToe, most games).
v_player_index := (p_data->>'player_index')::INT;
v_winner       := (v_player_index + 1) % 2;
RETURN jsonb_build_object(
  'state',           p_state,
  'pending_players', '[]'::jsonb,
  'outcome', jsonb_build_array(
    jsonb_build_object('player_index', v_winner,       'result', 'win',  'placement', 1, 'team_index', v_winner),
    jsonb_build_object('player_index', v_player_index, 'result', 'loss', 'placement', 2, 'team_index', v_player_index)
  ),
  'rng_seed', p_rng_seed
);
```

```sql
-- Skip: pass the turn to the next player, game continues (some card games).
v_player_index := (p_data->>'player_index')::INT;
RETURN jsonb_build_object(
  'state',           p_state,
  'pending_players', to_jsonb(ARRAY[(v_player_index + 1) % 2]),
  'rng_seed',        p_rng_seed
);
```

Always `RAISE` on unrecognised types — a loud error is better than silently producing wrong game state.

---

### Hook 3: `game_compute_observation(p_state, p_pending, p_player_index, p_participant_count, p_config, p_is_replay)` → envelope

Called once per participant by `update_all_observations` (after every action), by `start_game`, and by `get_replay` for every historical version. **Perfect-info games do not override this** — the default passthrough is already implemented.

Override for hidden-info games to strip opponent cards/hands and optionally narrow `pending_players`. Use `p_is_replay` to reveal information post-game (e.g. show all hole cards in a Poker replay).

```sql
CREATE OR REPLACE FUNCTION private.game_compute_observation(
  p_state             JSONB,
  p_pending_players   INT[],
  p_player_index      INT,
  p_participant_count INT,
  p_config            JSONB,
  p_is_replay         BOOLEAN DEFAULT FALSE  -- TRUE only from get_replay
)
RETURNS JSONB AS $$
BEGIN
  RETURN jsonb_build_object(
    'data',            p_state,
    'pending_players', to_jsonb(p_pending_players)
  );
END;
$$ LANGUAGE plpgsql STABLE SET search_path = '';
```

**`p_is_replay` usage example** (hidden-info game like Poker):
```sql
-- During live play: strip opponent hole cards.
-- During replay: reveal all hole cards so players can review the hand history.
IF p_is_replay THEN
  -- Return full state including all players' hole cards.
  RETURN jsonb_build_object('data', p_state, 'pending_players', to_jsonb(p_pending_players));
ELSE
  -- Strip the cards of all players except p_player_index.
  RETURN jsonb_build_object('data', private.strip_opponent_hands(p_state, p_player_index), ...);
END IF;
```

Note: `DEFAULT FALSE` means all existing callers (`update_all_observations`, `start_game`) continue to work without change — they never pass the 6th argument.

---

## Timing and the Hook Contract

Infra owns all clock logic. The hooks interact with timing through a single optional field: `turn_seconds`.

### How timing works end-to-end

**At game creation**, the host selects a timing mode via `create_game`. These are mutually exclusive — you cannot set both `turn_seconds` and `budget_seconds`.

**After each action**, infra applies the deadline precedence chain (see `engine_architecture.md §3`).

**When the hook returns `turn_seconds`**, infra uses that as the deadline for this action only and does not touch any player's bank. Use this for phase-specific windows regardless of the game's overall timing mode.

**In budget mode**, bank deduction happens automatically — the hook does not implement it. The hook only needs to handle the consequence of a timeout action, not the clock itself.

**When time expires**, infra calls `game_handle_system_action` with `p_action_type = 'timeout'`. The client-side `trigger_turn_expiry` RPC nudges the server immediately when a client detects the deadline — the cron job is just a backstop. Any active participant can call it safely; the server validates under lock.

> **Budget mode constraint:** budget mode must only be used in games where at most one player is pending at any given time. If your game has phases where multiple players are pending simultaneously, use `turn_seconds` for those phases. See `engine_architecture.md §3` for the full reasoning.

---

## RPC Functions Reference (Infra — Do Not Modify)

| RPC | Description |
|-----|-------------|
| `create_game(access, turn_seconds, budget_seconds, increment_seconds, min_players, max_players, config, rated_preference)` | Creates the game row with a unique `short_code` (retry on collision); adds creator as participant 0. Validates timing exclusivity and player count range. Derives `rated` and `rating_pool` server-side via `game_rating_pool()` — `rated_preference` is overridden to false if the hook returns `NULL`. |
| `join_game(game_id)` | Adds a participant; rejects if already at `max_players`; transitions to `ready` when count ≥ `min_players`. For `friends` access games, validates the caller is an accepted friend of the creator via `relationships`. |
| `join_game_by_code(code)` | Looks up a game by `short_code`, delegates to `join_game`. Returns the game ID. |
| `leave_game(game_id)` | Non-creator participants leave a `waiting` or `ready` game. Transitions back to `waiting` if count drops below `min_players`. |
| `start_game(game_id)` | Calls `game_initial_state`; creates `game_states` and per-player `observations` (via `game_compute_observation`); initialises `player_times` if budget mode; marks game `active`. |
| `cancel_game(game_id)` | Host aborts a `waiting` or `ready` game. Sets status to `aborted`. |
| `forfeit_game(game_id)` | Any participant forfeits an active game. Row-locks `games` (no version check — forfeit is unconditional), calls `game_handle_system_action` with `p_action_type = 'forfeit'`. |
| `submit_action(game_id, data, expected_version)` | Row-locks `games` (serializes all concurrent writers); validates version and deadline; gates on `pending_players`; calls `game_apply_action`; deducts bank (budget mode); applies deadline chain; fans out per-player observations; writes `game_outcomes` and finishes game on non-null outcome. |
| `trigger_turn_expiry(game_id)` | Client-side nudge when the client detects the deadline has passed. Safe for any participant to call; server validates under lock. |
| `get_replay(game_id)` | Returns the caller's observation slice at every historical state version as a JSONB array. Each frame: `{version, data, pending_players, created_at, action_type, action_data, action_player_index}`. `action_*` fields are `null` for version 0 (initial state). Only available for finished games; caller must be a participant. Post-game hidden-info reveal is controlled by `game_compute_observation` with `p_is_replay = true`. |
| `send_friend_request(target_user_id)` | Creates a `pending` relationship. Auto-accepts if the target already sent a request. |
| `accept_friend_request(target_user_id)` | Transitions a `pending` relationship to `accepted`. |
| `remove_friend(target_user_id)` | Deletes the relationship row (works for both accepted and pending). |
| `search_users(query)` | Returns up to 20 human-only results matching by username or display name (ILIKE, trigram-indexed). Queries `users`/`user_profiles` directly — bots never appear in results. |
| `get_players(ids)` | Returns public identity (id, username, display_name, avatar_url) for the given UUID array. Covers both humans and bots via a UNION. Used by `PlayerRepository` / `playerInfoCacheProvider` — game implementors do not call this directly. |
| `get_lobby_games(cursor, limit)` | Public waiting/ready games with embedded participants. Cursor-paginated. Requires authentication — anonymous browsing is not permitted. |
| `get_friends_games(cursor, limit)` | Friends-access games from accepted friends, plus the caller's own rooms, with participants and `is_participant` flag. |

---

## Testing Your Game

**Unit tests** for game logic:
```dart
test('valid action is accepted', () {
  final engine = MyGameEngine(const GameConfigData());
  final obs = ObservationData(board: List.filled(9, 0), actionCount: 0);
  expect(
    engine.isValidAction(obs, [0], ActionData(position: 4), 0),
    isTrue,
  );
});
```

**Manual testing**:
1. `supabase db reset` — applies all migrations cleanly.
2. Create a game with the target timing mode and play through to completion.
3. Verify `game_outcomes` contains the correct results.
4. For budget mode: confirm `player_times` updates after each move and `turn_deadline` reflects the next player's bank.
5. Trigger a timeout: let the deadline pass without acting, confirm cron fires `expire_turn`, confirm the hook's timeout consequence is applied.
6. Test forfeit: click forfeit in the game screen, confirm `game_handle_system_action` is called with `p_action_type = 'forfeit'`, confirm `game_outcomes` reflect the expected result.
7. Test leave: join as a non-host, call `leave_game`, confirm participant is removed and game status transitions correctly.
8. Test join-by-code: create a private/friends game, note the `short_code` displayed in the pre-game waiting room, join from another account using the code via the home screen's "Join via Code" dialog. If `APP_HOST` is configured, a QR code for the invite deep link is also shown — scan it with the second device to verify the deep link opens the join flow directly.
9. Test friends access: create a `friends` access game, confirm a non-friend cannot join, add friend, confirm friend can then join.
10. Test rating pool derivation: create a public Rapid game with rated preference on → `games.rated = true`, `games.rating_pool = 'rapid'`. Create an untimed public game → `games.rated = false`, `games.rating_pool = null`. Create a private game with rated preference on → `games.rated = false` (server overrides preference because pool is null for private games).
11. Test rating update: play a rated game to completion → `player_ratings` rows created/updated, `rating_history` rows inserted for each player. Requires `serverless_base_url` in `private.app_config` and `serverless_secret` in Vault — both are seeded automatically by `supabase db reset`.
12. Test idempotency: simulate the edge function being called twice for the same `game_id` → the second call's insert is rejected by the `rating_history` unique indexes (the call errors, but no duplicate rows are created and ratings are not double-applied).
13. `flutter analyze` → zero errors.

---

## Domain Configuration

### What `APP_HOST` Controls

`APP_HOST` in your app's `.env` is the authoritative source for the game's subdomain (e.g. `mygame.example.com`). The app reads it via `Env.appHost` (your app's `lib/env/env.dart`), passes it into `EngineConfig.appHost`, and the framework generates invite links from `appConfigProvider`.

When `APP_HOST` is set, the pre-game waiting room automatically shows a QR code (via `qr_flutter`) encoding the invite deep link (`https://<APP_HOST>/join/<short_code>`), alongside the copy-code and share-link buttons. When `APP_HOST` is not set, the QR code and share button are both hidden.

However, Android and iOS verify domain ownership at **install time** by fetching files from the host. Their configs are compiled into the app binary — they cannot be changed at runtime. This means the host is declared in **four places** that must always be kept in sync.

### What `LEGAL_HOST` Controls

`LEGAL_HOST` in your app's `.env` is the root domain where the terms of service and privacy policy pages are hosted (e.g. `example.com`). The app reads it via `Env.legalHost`, passes it into `EngineConfig.legalHost`, and the settings screen builds terms/privacy links via `legalPageUrl()` (`lib/core/utils/deep_links.dart`).

This is intentionally **separate from `APP_HOST`** for a critical reason: the App Links / Universal Links deep link configuration only covers `APP_HOST` (the game subdomain). If the terms and privacy URLs were built on `APP_HOST`, the OS would intercept them as deep links and route them back into the app rather than opening them in the browser. By using the root domain, which has no deep link configuration, the in-app browser opens them directly.

The terms/privacy tiles in the settings screen are conditionally shown — they only appear when `LEGAL_HOST` is set. Add it to `.env`:

```
LEGAL_HOST=eigeninteractive.com
```

Then add `LEGAL_HOST` as a GitHub Actions secret (repo Settings → Secrets → Actions) and ensure the CI workflow writes it to `.env` (already done in `android.yml`).

### The Four Places to Update

When the domain changes (e.g. from `mygame.example.com` to `newgame.example.com`), update all four of the following atomically:

#### 1. `.env`

```
APP_HOST=mygame.eigeninteractive.com
```

This drives `gameInviteLink()` at runtime. After changing, re-run the envied code generator:

```bash
dart run build_runner build
```

#### 2. `android/app/src/main/AndroidManifest.xml`

Change `android:host` in the App Links `<intent-filter>`:

```xml
<data
    android:scheme="https"
    android:host="mygame.eigeninteractive.com"/>
```

Android fetches `https://<host>/.well-known/assetlinks.json` at install time to verify this filter. If the host here doesn't match the deployed `assetlinks.json`, App Links silently falls back to the browser.

> **Do not remove** `android:enableOnBackInvokedCallback="true"` from the `<activity>` element when editing this file. That flag opts the app into the Android 14+ predictive back gesture API. Its absence silently disables predictive back for all users on Android 14+.

#### 3. `ios/Runner/Runner.entitlements`

Change the `applinks:` value:

```xml
<array>
    <string>applinks:mygame.eigeninteractive.com</string>
</array>
```

iOS fetches `https://<host>/.well-known/apple-app-site-association` via Apple's CDN at install time.

**Xcode step (required):** After editing this file, open Xcode → select the Runner target → Signing & Capabilities → verify Associated Domains lists `applinks:mygame.eigeninteractive.com`. If the entry is stale or missing, remove it and re-add it. The entitlement file alone is not enough — it must be wired into the Xcode project.

#### 4. `src/games.ts` in the Cloudflare Worker repo

The key in the `games` map is the subdomain prefix. To rename a game's subdomain, update the key and re-deploy:

```typescript
export const games: Record<string, GameConfig> = {
  mygame: {   // was: strategy
    name: 'My Game',
    // ...
  },
};
```

Then:

```bash
npx wrangler deploy
```

See `docs/web.md` for full Cloudflare Worker setup.

### Deployment Notes

- **Android and iOS changes require a new app release** — the host is baked into the binary at build time. Users on old builds will not have deep link interception for the new domain.
- **Cloudflare Worker changes take effect immediately** after `wrangler deploy`. If you change the subdomain, the old subdomain stops working immediately. Coordinate the Worker deploy with the app release.

### Verification After Changing the Domain

After deploying the Worker and before submitting the app to the stores, confirm the verification files are correct:

- **Android:** [Google Digital Asset Links validator](https://developers.google.com/digital-asset-links/tools/generator) — paste the new domain and package name; it fetches and validates `assetlinks.json`.
- **iOS:** [AASA validator](https://yurl.chayev.com/) — paste the new domain; it fetches and validates `apple-app-site-association`.

Common failure causes:
- SHA-256 fingerprint in `assetlinks.json` doesn't match the signing keystore — re-run `keytool` and compare.
- iOS Team ID mismatch — find it at [developer.apple.com/account](https://developer.apple.com/account) under Membership.
- The verification file is served with a redirect — Cloudflare's orange cloud must be on and the Worker must not redirect `/.well-known/*` paths.

---

## Splash Screen Assets

The splash screen is **infra-owned**. Game implementors do not call `FlutterNativeSplash.remove()` or touch `AppStartup` — the remove is driven by `authStateChangesProvider.future` in `lib/core/startup/app_startup.dart` and fires as soon as Supabase emits `INITIAL_SESSION`. See `engine_architecture.md §13` for the full architecture, sequence diagram, and generated file inventory.

When deploying a new game app, provide the logo assets and regenerate the platform files.

### Asset Files to Create

Place in `assets/splash/` and declare the folder in `pubspec.yaml` under `flutter: assets:`.

| File | Size | Notes |
|------|------|-------|
| `assets/splash/logo.png` | **1152 × 1152 px** | Light-mode logo. Keep artwork within the inner **640 px** — the outer ring is cropped on Android 12's circular icon mask. PNG with transparency recommended. |
| `assets/splash/logo_dark.png` | **1152 × 1152 px** | Dark-mode logo (white/light version for the dark `#141218` background). |

Optional:

| File | Size | Notes |
|------|------|-------|
| `assets/splash/branding.png` | ≥ 600 px wide | Studio name / tagline shown at screen bottom. Add `branding:` and `branding_bottom_padding:` to the config block. |
| `assets/splash/branding_dark.png` | ≥ 600 px wide | Dark variant of branding image. |

### `pubspec.yaml` — add `image:` fields once assets exist

The `flutter_native_splash:` block already configures background colors. Add the image lines when the assets are ready:

```yaml
flutter_native_splash:
  color: "#FFFBFF"
  color_dark: "#141218"
  image: assets/splash/logo.png           # add this
  image_dark: assets/splash/logo_dark.png # add this

  android_12:
    color: "#FFFBFF"
    color_dark: "#141218"
    image: assets/splash/logo.png           # add this
    image_dark: assets/splash/logo_dark.png # add this
    icon_background_color: "#FFFBFF"
    icon_background_color_dark: "#141218"
```

### Regenerate After Any Asset or Config Change

```bash
dart run flutter_native_splash:create
```

### Checklist

- [ ] Create `assets/splash/logo.png` and `logo_dark.png` at 1152 × 1152 px
- [ ] Add `assets/splash/` to `flutter: assets:` in `pubspec.yaml`
- [ ] Add `image:` / `image_dark:` to both the root and `android_12:` config blocks
- [ ] Run `dart run flutter_native_splash:create`
- [ ] Verify on a physical device: logo appears on the splash, splash disappears after auth resolves (not on a fixed timer), both light and dark OS themes show the correct logo variant

---

## In-App Review

In-app review is **infra-owned**. Game implementors do not call `ReviewNotifier` or import `review_notifier.dart` — the win trigger fires automatically from `game_screen.dart` whenever the local player's `OutcomeResult` is `win`.

The prompt appears every 5 wins (lifetime, persisted across sessions). The OS silently enforces its own quota (3× per year on both platforms). All wins count — game type, timing mode, and rated status are irrelevant.

See `engine_architecture.md §15` for the full architecture and the `ReviewNotifier` source.

---

## In-App Updates (Android)

In-app updates are **infra-owned**. Game implementors do not touch `UpdateNotifier` or the update lifecycle — everything is driven automatically from `AppStartup` and `ShellScaffold`.

- **Immediate update** — full-screen system UI; skipped during active games and retried on the next resume.
- **Flexible update** — background download; `ShellScaffold` shows a snackbar with a "Restart" action when ready.

See `engine_architecture.md §15` for the full architecture and decision log.

---

## Analytics & Push Notifications

Both are **infra-owned**. Game implementors do not import `analytics_service.dart`,
`firebase_notification_service.dart`, or any Firebase package — all events and
notifications fire automatically from core infrastructure.

**Android notification icon:** `android/app/src/main/res/drawable/ic_notification.xml` is the one file in this area that is **not** fully infra-owned. It contains a monochrome silhouette of the app logo used for Android notification icons (API 21+ requires this — the full-colour launcher icon renders as a white box). When deploying a new game, replace this vector with one matching the new app's brand. See `engine_architecture.md §20` for the three places it is referenced and the rationale.

### Analytics events

| Event | When it fires |
|-------|--------------|
| `game_created` | After the New Game dialog creates the game |
| `game_started` | When the game transitions to `active` status |
| `game_finished` | When outcomes arrive for the finished game |
| `forfeit` | After a forfeit RPC call succeeds |
| `join_by_code` | After joining by code succeeds |
| `friend_request_sent` | After sending a friend request succeeds |
| `friend_accepted` | After accepting a friend request succeeds |

### Push notifications sent automatically

| Title | Body | Trigger |
|---|---|---|
| "Your turn" | "It's your move." | `observations` INSERT or UPDATE where the user's player index enters `pending_players` (INSERT covers the game's first move) |
| "{creator} started a game" | "Join now to play." | A `friends`-access game is created by an accepted friend (public games are lobby-discoverable, not pushed) |
| "{sender} wants to be friends" | "Tap to respond." | A friend request is sent to the user |

### Setup

Firebase is mandatory. The following files are generated by `flutterfire configure` and are **gitignored** — they are instance-specific and must not be committed:

| File | Platform |
|---|---|
| `lib/firebase_options.dart` | Dart (all platforms) |
| `android/app/google-services.json` | Android native |
| `ios/Runner/GoogleService-Info.plist` | iOS native |
| `firebase.json` | FlutterFire CLI metadata only — not needed in CI |

Run once per deployment:
```bash
npm install -g firebase-tools && firebase login
dart pub global activate flutterfire_cli
flutterfire configure   # select Android and iOS only
```

#### CI secrets required

Encode each file and add as GitHub Actions secrets:

```bash
base64 -i lib/firebase_options.dart           | pbcopy  # → FIREBASE_OPTIONS_DART_BASE64
base64 -i android/app/google-services.json    | pbcopy  # → GOOGLE_SERVICES_JSON_BASE64
base64 -i ios/Runner/GoogleService-Info.plist | pbcopy  # → GOOGLE_SERVICE_INFO_PLIST_BASE64 (iOS CI)
```

See `engine_architecture.md §14` (analytics), `engine_architecture.md §18` (obfuscation and symbol upload), and `engine_architecture.md §20` (push notifications) for the full implementation, CI workflow details, and required Vault secrets.

---

## Haptic Feedback

Haptic feedback is **infra-owned**. Game implementors do not import `flutter/services.dart` or call `HapticFeedback` directly — all three moments fire automatically from `game_screen.dart`.

| Moment | Haptic | Trigger |
|--------|--------|---------|
| Valid action submitted | `lightImpact` | Fires in `_submitAction` before the RPC call |
| Win outcome arrives | `heavyImpact` | Fires in `_onGameOutcomes` when the local player's result is `win` |
| Invalid move attempted | `selectionClick` | Fires via the `onInvalidAction` callback (see below) |

### The `onInvalidAction` Callback

`buildContent()` receives `onInvalidAction: VoidCallback`. Call it in the rejection branch of your tap handler — infra decides the haptic:

```dart
onCellTap: (position) {
  final action = ActionData(position: position);
  if (engine.isValidAction(observation, pendingPlayers, action, myPlayerIndex)) {
    onAction(action.toJson());
  } else {
    onInvalidAction(); // do not call HapticFeedback directly
  }
},
```

Pass it through from `GameModule.buildContent()` to your content widget as a required field, exactly as shown in the content widget template above.

See `engine_architecture.md §16` for the full deduplication logic and file inventory.

## External Console Setup

Steps required in external dashboards before the backend checklist can be completed. Do these once per deployment.

### 1. Firebase Console

1. Go to [console.firebase.google.com](https://console.firebase.google.com) → **Create a project** (enable Google Analytics during setup).
2. Run `flutterfire configure` — it registers the Android and iOS apps inside your project automatically. You do not need to add apps manually in the console.
3. **Add SHA fingerprints** to the Android app (required for Google Sign-In on Android — `flutterfire` does not add these):
   - Firebase Console → Android app → **SHA certificate fingerprints** → add debug + upload fingerprints.
   - See [§SHA Fingerprints](#sha-fingerprints-for-android) below for the `keytool` commands.
4. Enable **Crashlytics**: Build → Crashlytics → Get started.
5. Verify **Cloud Messaging** is enabled: Project Settings → Cloud Messaging.
6. **Create a service account** for edge functions:
   - Project Settings → Service Accounts → **Generate new private key**.
   - Open the downloaded JSON and copy `client_email` → `FIREBASE_CLIENT_EMAIL` and `private_key` → `FIREBASE_PRIVATE_KEY`. Delete the file — only these two fields are needed.

### 2. Google Cloud Console — OAuth

Firebase auto-creates a paired Google Cloud project. Open it from Firebase Console → Project Settings → the Google Cloud Console link.

1. **Configure the OAuth consent screen**: APIs & Services → OAuth consent screen.
   - User type: External (or Internal for internal testing).
   - Fill in app name, support email, developer contact, and authorized domains (`<ref>.supabase.co` and your app domain).
2. **Create a Web OAuth client**: APIs & Services → Credentials → Create credentials → OAuth client ID.
   - Application type: **Web application**.
   - Authorized redirect URI: `https://<supabase-project-ref>.supabase.co/auth/v1/callback`.
   - Note the **Client ID** and **Client Secret** — both go into Supabase Auth → Providers → Google.

> Android and iOS OAuth clients are created automatically when you register apps in Firebase Console. The Web client is the one Supabase needs for the server-side OAuth flow.

### 3. Supabase Auth — Google Provider

Supabase Dashboard → Authentication → Providers → **Google**:
- Enable the provider.
- **Client ID (from Google Cloud Console)**: the Web OAuth Client ID from step 2.
- **Client Secret**: the Web OAuth Client Secret from step 2.

Authentication → URL Configuration → **Redirect URLs** → add your deep link scheme, e.g. `com.eigeninteractive.strategy://` (required for the native OAuth callback).

### 4. APNs — iOS Push Notifications

Required before FCM can deliver push notifications on iOS.

1. [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles → **Keys** → create a key with **Apple Push Notifications service (APNs)** enabled.
2. Download the `.p8` file (only available once). Note the **Key ID** and **Team ID** (Membership page).
3. Firebase Console → Project Settings → Cloud Messaging → **Apple app configuration** → upload the `.p8` file with the Key ID and Team ID.

### SHA Fingerprints for Android

Firebase Console requires SHA-1 (and optionally SHA-256) of every certificate that signs the app, because Google Sign-In validates the calling app's certificate at runtime.

**Step 1 — Add the debug key now** (lets you test Sign-In in local dev builds):

```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey \
  -storepass android -keypass android
```

Copy the SHA-1 (and SHA-256) into Firebase Console → Android app → SHA certificate fingerprints.

**Step 2 — Add the Play Store app signing key after your first upload** (required for Sign-In to work for users who installed from the store):

Play App Signing is mandatory for new apps. Google re-signs your upload APK/AAB with their own key before distributing it, so the app on users' devices is signed with Google's key — not yours. If you only add your upload key's SHA, Sign-In will fail in production.

After your first Play Store upload:
1. Google Play Console → your app → Release → Setup → **App signing**
2. Under **App signing key certificate**, copy the SHA-1 and SHA-256.
3. Add both to Firebase Console → Android app → SHA certificate fingerprints.

Your upload keystore SHA is optional — only needed if you test a locally-signed release APK before uploading.

---

## Backend / Supabase Production Checklist

**External console (complete before `flutterfire configure`):**
- [ ] Firebase project created with Google Analytics enabled
- [ ] `flutterfire configure` run — registers Android and iOS apps automatically
- [ ] Debug keystore SHA-1 added to Firebase Console → Android app → SHA certificate fingerprints (enables Sign-In in dev builds)
- [ ] **After first Play Store upload:** Play Store app signing key SHA-1 and SHA-256 added to Firebase Console (Google Play Console → Release → Setup → App signing → App signing key certificate) — required for Sign-In to work for store installs
- [ ] Crashlytics enabled (Build → Crashlytics → Get started)
- [ ] Firebase service account key generated (Project Settings → Service Accounts → Generate new private key) — `client_email` → `FIREBASE_CLIENT_EMAIL`, `private_key` → `FIREBASE_PRIVATE_KEY`, file deleted
- [ ] OAuth consent screen configured in Google Cloud Console
- [ ] Web OAuth 2.0 client created with Supabase redirect URI (`https://<ref>.supabase.co/auth/v1/callback`)
- [ ] Supabase Auth → Providers → Google enabled with Web Client ID and Client Secret
- [ ] Supabase Auth → URL Configuration → Redirect URLs includes the app's deep link scheme
- [ ] APNs key created in Apple Developer Console and uploaded to Firebase Console → Cloud Messaging (iOS)

**Backend:**
- [ ] `expire_all_turns` pg_cron job confirmed active in production (check Dashboard → Database → Cron Jobs)
- [ ] `serverless_base_url` set in `private.app_config` for production project
- [ ] `serverless_secret` created in Supabase Vault for production project and matches `SERVERLESS_SECRET` edge function env var
- [ ] `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`, `FIREBASE_PROJECT_ID`, and `SERVERLESS_SECRET` set as edge function secrets via `supabase secrets set` (see `engine_architecture.md §20` for full commands)
- [ ] `supabase functions deploy` run to deploy all edge functions (`update-ratings`, `refresh-fcm-token`) — see `engine_architecture.md §21`
- [ ] `refresh-fcm-token` pg_cron job confirmed active (fires every 50 min; seeds `private.app_config` with `fcm_access_token` and `firebase_project_id` on first run)
- [ ] Run `flutterfire configure` (Android + iOS) to generate `lib/firebase_options.dart`, `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist` — all gitignored, do not commit
- [ ] Base64-encode the three files and add as GitHub Actions secrets: `FIREBASE_OPTIONS_DART_BASE64`, `GOOGLE_SERVICES_JSON_BASE64`, `GOOGLE_SERVICE_INFO_PLIST_BASE64`
- [ ] Replace `android/app/src/main/res/drawable/ic_notification.xml` with a monochrome silhouette of the new app's launcher icon foreground (Android API 21+ renders the full-colour launcher icon as a solid white box)
- [ ] Add `LEGAL_HOST` as a GitHub Actions secret (e.g. `eigeninteractive.com`) — controls the terms/privacy links in the settings screen
- [ ] PITR (Point-in-Time Recovery) enabled on Supabase Pro — `game_states` is append-only history, losing data affects rated game audit trail
- [ ] Rate limiting enabled on `submit_action` and `create_game` RPCs in Supabase Dashboard → API → Rate Limits
- [ ] Supavisor connection pooler: use **session mode** for `submit_action` and `expire_turn` (they use `FOR UPDATE`); transaction mode for read RPCs
- [ ] Realtime enabled only on tables that need it (`observations`, `games`, `relationships`) — disable on others to reduce noise
- [ ] Row-level security verified on all tables (run `SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public'`)

---

## Shipping the App (Android / Google Play)

Store packaging and release are **app-owned** (the engine has no app to ship).
The reference setup lives in the `strategy` app — copy it for a new game:

- **`fastlane/`** — `Fastfile` with `android internal` / `android production` lanes
  (`upload_to_play_store` with the built AAB) and `Appfile` (the `package_name`),
  plus a `Gemfile` for the `fastlane` gem.
- **CI** (`.github/workflows/android.yml`) — the `build` job builds a **signed,
  obfuscated release AAB** (`flutter build appbundle --release --obfuscate
  --split-debug-info=…`), and the `deploy` job runs `bundle exec fastlane android
  internal` to push it to the Play internal track.

Per-app setup:
- Create an upload keystore; add `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
  `KEY_ALIAS`, `KEY_PASSWORD` as GitHub Actions secrets (CI writes
  `android/key.properties` from them).
- Create a Google Play service account with the *Release* permission; add its
  JSON as `GOOGLE_PLAY_JSON_KEY` (used by fastlane `upload_to_play_store`).
- `applicationId` (Android) / bundle id (iOS) are the app's own store identity —
  set them per product (not derived from the engine).
- First upload must be done manually in the Play Console (to create the app
  listing); subsequent releases flow through fastlane.

iOS store submission (TestFlight/App Store) is not yet wired in the reference
app; add an `ios` fastlane lane when you target iOS.