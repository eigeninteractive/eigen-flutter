# Game Implementation Guide

This guide explains how to implement a new game using the **Eigen Engine**.

---

## Overview

Eigen Engine is a **whitelabel game engine** — the core infrastructure (auth,
networking, real-time updates, timing) is shared, while each game provides its
own rules and UI through two pieces:

- a **TypeScript `GameEngine`** — six methods (three core: `initialState`,
  `applyAction`, `computeObservation`; three optional: `ratingPool`,
  `handleEvent`, `botSeatable`) that the engine's edge function runs
  server-side (see **Backend Changes Required**), and
- a **Dart `GameModule`** — the client side (board rendering, action validation,
  and local twins of `ratingPool`/`botSeatable` for the create dialog and bot
  pickers).

The authoritative method signatures are the `GameEngine` interface in
`supabase/functions/_types/engine.types.ts`.

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
[README → Versioning & backward
compatibility](../README.md#versioning--backward-compatibility) for the full
dependency + release model.

**Fonts.** Nothing to do per app. The engine **bundles Inter as a package font**
(all 9 weights, declared under `fonts:` in the engine `pubspec.yaml`), so
Flutter includes it in every consuming app automatically and it **renders
offline from the first frame** — no `google_fonts`, no runtime fetch, no per-app
asset wiring. The theme references it as `packages/eigen_engine/Inter`. To
change the typeface, add the new family's weights to the engine's `fonts/` +
`pubspec.yaml` and update that one constant in `AppTheme`. (Engine maintainers
regenerate the Inter weights with `tool/download_fonts.sh`.)

**Recommended structure.** A single Flutter app with the game under a
`lib/game/` folder. The game ↔ engine boundary is already compiler-enforced (the
engine is a separate package), so a folder is enough; you don't need a separate
game package:

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
└── supabase/                     # config.toml + migrations + functions/_lib/game.ts
                                  #   (engine backend vendored; you own your migration
                                  #    + the TS gameEngine seam)
```

Engine contracts are imported from `package:eigen_engine/...` (or the
`package:eigen_engine/eigen_engine.dart` barrel); game files import each other
via `package:my_app/game/...`.

> _Optional (advanced):_ if you ever need to share one game across multiple apps
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

> **Note:** `Observation.data` in the core layer is `Map<String, dynamic>`. Your
> content widget receives this already deserialized into `ObservationData` at
> the game layer boundary (see step 5).

> **Evolving these models after launch.** Once real users have games in
> progress, these three payloads become a compatibility contract. Make new
> fields nullable or `@Default(...)` and give enums
> `@JsonKey(unknownEnumValue: …)`; a change that alters a field's meaning or the
> board/action shape is breaking and needs a `schema` bump on the game type, not
> an in-place edit. See [`engine_architecture.md`](engine_architecture.md) §24
> (Backward Compatibility).

---

### 2. Game Engine (`logic/`)

`BaseEngine` is intentionally minimal. It is responsible only for:

- `config` — the per-instance game configuration.
- `isValidAction` — local legality check for UX feedback only. Authoritative
  validation happens server-side in `applyAction`.
- Pure rendering helpers (e.g., "which cells form the winning line" for
  highlight rendering).

Player counts are declared on `GameCreationSpec`, and player identities arrive
via `PlayersContext` — the engine carries no player metadata.

Turn-gating, game-over detection, and winner derivation are **infra-level
facts**, surfaced via `observations.pending_players`, `games.status`, and
`game_outcomes`. The engine never re-derives them.

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

All four parameters are passed on every call so the contract stays uniform. Your
engine ignores whatever it doesn't need.

| Game                                            | `obs`                   | `pendingPlayers`                    | `action`        | `playerIndex`              |
| ----------------------------------------------- | ----------------------- | ----------------------------------- | --------------- | -------------------------- |
| **TicTacToe** (sequential, no ownership)        | board                   | ignored                             | target cell     | ignored                    |
| **Chess** (sequential, piece ownership)         | board                   | ignored                             | from/to squares | used — "is that my color?" |
| **Set** (any-player, race)                      | face-up cards           | used — "am I still eligible?"       | the set of 3    | ignored                    |
| **Rock-Paper-Scissors** (simultaneous)          | who has submitted       | used — "am I still pending?"        | my choice       | used — only update my slot |
| **Exploding Kittens** (sequential + interrupts) | hand, discard, deck top | used — main-turn vs. Nope interrupt | the card        | used — "do I hold this?"   |

Concrete examples:

- **Chess** — read `action.from`, look up the piece on `obs.board`, return false
  unless the piece color matches `playerIndex`.
- **Exploding Kittens** — if `action.card == Nope`, only check that
  `obs.hand[playerIndex]` contains a Nope (anyone may Nope, even if not in
  `pendingPlayers`). Otherwise, require `pendingPlayers.contains(playerIndex)`
  and that the played card is in hand.

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

The module is the single file that wires everything together and registers the
game with the engine. It implements `GameModule` from
`core/game/game_module.dart`.

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

  @override
  Widget buildRules(BuildContext context) => const MyGameRules();
}
```

`buildContent` takes a single
[`GameContentContext`](../lib/core/game/game_module.dart) and your content
widget consumes it directly (`MyGameContent(content: context)`) rather than
re-declaring and unpacking each field — so adding new infra data later never
changes the signature or forces every game to update. The context exposes the
two halves of the live game as separate members — `engine` (created once from
config, long-lived) and `frame` (the per-event observation snapshot:
`frame.observation`, `frame.pendingPlayers`, `frame.version`, `frame.timing`) —
plus `gameStatus`, `outcomes`, `actionPending`, `onAction`, `onInvalidAction`,
`playersContext`, and the convenience getters `myPlayerIndex` (delegates to
`playersContext.myPlayerIndex`) and `timing` (delegates to `frame.timing`).

`buildRules` is required and returns your game's how-to-play content for the
engine's About page. Return plain, non-scrolling content (e.g. a `Column` of
sections); the About page supplies the scroll container, padding and app chrome.
It may be interactive and read `Theme.of(context)`.

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

| Field           | Type                            | Default                        | Description                                                                                                |
| --------------- | ------------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `minPlayers`    | `int`                           | required                       | Minimum players to transition game to `ready`.                                                             |
| `maxPlayers`    | `int`                           | required                       | Maximum players allowed to join. Must be ≥ `minPlayers`.                                                   |
| `timingConfigs` | `Map<String, TimingModeConfig>` | `{'Untimed': UntimedConfig()}` | Ordered map of timing options. Keys become `SegmentedButton` labels; insertion order is the display order. |
| `defaultConfig` | `Map<String, dynamic>`          | `{}`                           | Seed value for the config map when `buildCreationConfig` is null.                                          |

#### Timing config types

| Type                                                          | Controls rendered                             | Key fields                            | Infra constraint       |
| ------------------------------------------------------------- | --------------------------------------------- | ------------------------------------- | ---------------------- |
| `UntimedConfig()`                                             | None                                          | —                                     | —                      |
| `PerActionConfig(min, max, presets)`                          | Preset chips + slider                         | `minSeconds` ≥ 30, `maxSeconds` > min | `turn_seconds` ≥ 30    |
| `BudgetConfig(minBudget, maxBudget, minInc, maxInc, presets)` | Bank slider + increment slider + preset chips | `minBudgetSeconds` ≥ 120              | `budget_seconds` ≥ 120 |

Multiple entries of the same subtype are allowed — a game can offer both a
`'Blitz'` and a `'Daily'` `PerActionConfig` as distinct named segments.
`BudgetConfig` must only appear in games where at most one player is pending at
a time (see `engine_architecture.md §3`).

#### Variable player counts

`minPlayers` and `maxPlayers` can differ to support lobbies that start with a
range of player counts (e.g. `min: 2, max: 6` for a party game). `app_join_game`
accepts participants until `max_players` is reached. The game transitions to
`ready` when the count hits `min_players` and the host can start at any point
from there.

Override `playersForConfig` when the valid range depends on a config choice made
at creation time:

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

The widget manages its own visual state. The dialog captures the latest value
via `onChanged` into a plain field (no `setState`) and passes it to the
`game/create` route at submit.

---

### 5. Content Widget (`presentation/my_game_content.dart`)

Receives pre-parsed, typed data. No JSON parsing or engine construction here —
both happen once per network event in the session provider.

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

The infra layer resolves all player identities before calling `buildContent()`.
The game implementor receives a `PlayersContext` with guaranteed non-nullable
data — no null checks, no loading states, no provider watches needed.

For finished games where a participant's account has since been deleted, infra
provides a **synthetic identity** (`displayName: 'Deleted User'`,
`username: 'player_$index'`) so the seat is always populated. Check
`player.isDeleted` before calling `PlayerProfileSheet.show` — the synthetic
identity has no real database record to look up.

> **Game identity vs social identity:** `PlayerInfo` and
> `playerInfoCacheProvider` cover both humans and bots — they are the right tool
> inside game screens, lobby cards, and anywhere a game seat needs a
> name/avatar. Social features (friend search, friend requests) are human-only
> and never surface bots. Game code should not check player type to decide
> whether to display identity — treat all `GamePlayer` entries uniformly; use
> `GamePlayer.type` only when game rules need to distinguish (e.g. "is this a
> bot seat I should auto-play?").

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

| Field         | Type              | Description                                                                                                                                    |
| ------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `playerIndex` | `int`             | 0-based seat in the game                                                                                                                       |
| `type`        | `ParticipantType` | The type of this player (human, bot)                                                                                                           |
| `info`        | `PlayerInfo`      | Resolved identity (username, displayName, avatarUrl)                                                                                           |
| `isDeleted`   | `bool`            | True when the account no longer exists. `info` is a synthetic placeholder — do not pass `info.id` to identity lookups or `PlayerProfileSheet`. |

> Per-game **roles** (host/guest, team, faction, dealer…) are _not_ an infra
> concept — they live in your game's observation/state JSON, where your engine
> and `computeObservation` hook can shape them freely. Infra only tracks
> the seat index (`playerIndex`) and `type`.

### `PlayersContext` API

| Member             | Type                   | Description                            |
| ------------------ | ---------------------- | -------------------------------------- |
| `players`          | `Map<int, GamePlayer>` | All players keyed by index             |
| `myPlayerIndex`    | `int`                  | Current user's seat (-1 if spectating) |
| `operator [](int)` | `GamePlayer`           | Non-nullable access by index           |
| `me`               | `GamePlayer`           | Convenience for `this[myPlayerIndex]`  |

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
- `onTap` is optional — when `null` the avatar is non-interactive. Pass a
  callback to open `PlayerProfileSheet`; guard deleted players with
  `player.isDeleted` so the synthetic identity is never passed to identity
  lookups.

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

The game screen only calls `buildContent()` after `gamePlayersProvider(gameId)`
has fully resolved. This means:

- `playersContext[i]` never returns null — it's typed as `GamePlayer`, not
  `GamePlayer?`
- No `AsyncValue` handling needed in game content widgets
- No shimmer/loading fallbacks required for player identity
- If identity data is still loading, the game screen shows its own loading
  indicator before your widget is ever constructed
- **Deleted accounts:** for finished games where a participant later deleted
  their account, infra returns a synthetic identity
  (`displayName: 'Deleted User'`, `username: 'player_$playerIndex'`). The seat
  is always populated, but `PlayerProfileSheet.show` must not be called — guard
  with `player.isDeleted`.

---

## Adding Bots

Bots are **optional** — a game with no bots needs nothing here. A bot is the
same pure function the engine already drives for humans (**observation → legal
action**), so once seated a bot reuses the entire turn/commit/rating spine.
There are two kinds, and they differ only in _who computes the move_ and _how
the move is authenticated_. See `engine_architecture.md §26` for the
architecture and security model (invariants, seating, auth); this is the
implementor's how-to.

### Local bots (your code, runs on the player's device)

Use these for **solo play** (one human + bot opponents), including hidden-info
games — they are safe there because there is no other human to cheat against.
Local bots run on the present human's client, so a local-bot game is always
**untimed** (no deadline backstop needed; for a _timed_ AI game use a server
bot). The contract is the only bot surface you implement.

1. **Implement `LocalBot`** in your game package (alongside your `GameModule`,
   never in the engine). A bot is a **pure reducer**
   `(observation, state) → (action,
   nextState)`; the fourth type param is
   your bot's private per-(game, seat) brain (`TState`). A bot that needs no
   memory uses `Null`:

   ```dart
   class MinimaxBot extends LocalBot<MyObservation, MyAction, MyConfig, Null> {
     const MinimaxBot({required this.username, this.depth = 4});

     @override
     final String username; // must equal a bots.username row

     final int depth;

     @override
     Null createState({
       required BaseEngine<MyObservation, MyAction, MyConfig> engine,
       required int seatIndex,
       required Map<String, dynamic> config, // bots.config, may be empty
     }) => null; // stateless bot — a stateful one returns its initial brain

     @override
     ({MyAction action, Null state}) chooseAction({
       required BaseEngine<MyObservation, MyAction, MyConfig> engine,
       required MyObservation observation,   // already typed — no cast
       required int seatIndex,
       required Null state,
     }) {
       // ...pick a legal move (use `engine` for validation/legal moves)...
       return (action: MyAction(cell: bestCell), state: null);
     }
   }
   ```

   A **stateful** bot (an MCTS tree, a Stratego/poker belief model) sets
   `TState` to its brain type: `createState` seeds it, and each `chooseAction`
   returns the **next** state — re-rooted to the played move, beliefs folded in
   — which the driver commits **only when the action is accepted**.

   `LocalBot` is generic over the same `<observation, action, config>` triple as
   your engine (plus `TState`), so you write it like the engine and get a fully
   typed `observation` in and a typed action out — **no casts, no hand-rolled
   JSON**. The driver serialises your action via `engine.serializeAction`, the
   same seam the human path uses, so the two can never drift.

   **The engine runs `chooseAction` off-thread** (`Isolate.run`), so heavy
   search never blocks a UI frame — no `compute()` of your own. In return it
   must be **pure** (never mutate `state` or touch the outside world; seed any
   randomness from `state` and return the advanced seed), and everything it
   touches — bot, engine, observation, action, `state` — must be
   **isolate-sendable** (plain data, no clients/ports). A bot needing **large
   static data** (a pretrained net) belongs **server-side**: it would be
   re-copied into the isolate every move.

   **What `chooseAction` returns is an action plus the next state** — the action
   is the same shape a human move produces (see _Designing action data_ below);
   you design it, and the server validates it in `applyAction`.

2. **Register instances** in your module — this presence _is_ the local-bot
   support flag (empty default ⇒ no bot UI):

   ```dart
   @override
   List<LocalBot> get localBots => const [
     MinimaxBot(username: 'easy_ai', depth: 2),
     MinimaxBot(username: 'hard_ai', depth: 6),
   ];
   ```

   One class can back several personas via constructor args **or** the DB
   `bots.config` handed to `createState` (N:1). The engine's driver matches a
   pending bot seat to the `localBots` entry whose `username` equals the seat's
   `bots.username`, runs `chooseAction`, and submits — you write no wake/submit
   plumbing.

3. **Insert a matching `bots` row** per persona (see SQL below) with
   `is_local = true`.

### Server bots (a remote endpoint you run, any language)

Use these for **multiplayer fill**, **rated** games, or "keep playing while the
app is closed". They also work in **solo solo play**, but only when the game is
**timed** — the server requires a deadline backstop for an unreachable bot, so
the Play-vs-AI picker offers server bots only once a timed mode is chosen (and
never to guests). They run outside this repo — the engine only talks to them
over HTTPS, so they implement no Dart contract. The whole protocol is ~40 lines
in any language with HMAC-SHA256 (verify wake → compute → sign → submit;
reference server below); the flow:

- On the bot's turn the engine `POST`s a **wake** to the row's `webhook_url`,
  carrying the observation:
  `{ game_id, bot_id, player_index, username, config,
  observation, version, pending_players, turn_deadline }`.
- The bot computes a move and `POST`s it to the **`bot/action`** edge-function
  route as `{ payload, signature }`, where `payload` is the signed JSON string
  `{ game_id, bot_id, player_index, version, data }`.

**Authentication** (handled for you; you provision one derived key):

Both directions use the **same per-bot HMAC key**, derived from the platform's
single master secret as `HMAC-SHA256(BOT_SIGNING_SECRET, bot_id)` — no per-bot
secret is stored anywhere. The bot is given this derived key once:

- **Wake (us → bot):** the engine sends `x-wake-signature` = base64 HMAC-SHA256
  of the exact request body; your bot recomputes it over the raw body and
  rejects on mismatch.
- **Action (bot → us):** your bot sends `signature` = base64 HMAC-SHA256 of
  the exact `payload` it posts; the `bot/action` route recomputes the key and
  verifies it. This is the real security boundary — the wake never authorizes a
  move (the server re-validates every action under lock), so a forged wake can
  at most waste the bot's compute.

So the bot deployment holds **one derived key** (it signs actions and verifies
wakes). Server-bot games must be **timed** (the turn deadline is the liveness
backstop for an unreachable bot).

**Reference server (Node 18+, built-in `crypto`).** The entire contract — verify
the wake, decide a move for _this_ seat, sign the action, submit before
`turn_deadline`. Sign over the **raw** request bytes (don't re-serialise), and
the bytes you sign must be **byte-identical** to the `payload` you send.

```js
import { createServer } from "node:http";
import { createHmac, timingSafeEqual } from "node:crypto";

const BOT_ID = process.env.BOT_ID;
const SECRET = process.env.BOT_KEY; // = HMAC-SHA256(BOT_SIGNING_SECRET, bot_id)
const ACTION_URL = process.env.ACTION_URL; // …/functions/v1/engine/bot/action
const ANON_KEY = process.env.SUPABASE_ANON_KEY;
const hmac = (s) => createHmac("sha256", SECRET).update(s).digest("base64");

createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", async () => {
    const raw = Buffer.concat(chunks); // the RAW bytes
    const a = Buffer.from(hmac(raw));
    const b = Buffer.from(req.headers["x-wake-signature"] ?? "");
    if (a.length !== b.length || !timingSafeEqual(a, b)) { // 1. verify wake
      res.writeHead(401).end();
      return;
    }
    res.writeHead(200).end(); // ack fast; act below

    const wake = JSON.parse(raw.toString("utf8"));
    const data = chooseMove(wake.observation, wake.player_index); // 2. your AI
    const payload = JSON.stringify({ // 3. sign the action
      game_id: wake.game_id,
      bot_id: BOT_ID,
      player_index: wake.player_index,
      version: wake.version,
      data,
    });
    const r = await fetch(ACTION_URL, { // 4. submit before deadline
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: ANON_KEY,
        Authorization: `Bearer ${ANON_KEY}`,
      },
      body: JSON.stringify({ payload, signature: hmac(payload) }),
    });
    if (!r.ok) console.warn("action rejected:", r.status, await r.text());
  });
}).listen(8080);
```

Handle the reply: `200` committed; a `Stale state`/seat-conflict error is a
benign race (the turn moved on) — drop it; `Unauthorized` means a bad MAC or
registration. The wake is fire-and-forget (the engine ignores your HTTP status),
so only the action call matters. The same loop is ~40 lines in Python
(`http.server` + `hmac`) or any language. The bare action submit as a
language-agnostic `curl`:

```bash
PAYLOAD='{"game_id":"…","bot_id":"…","player_index":1,"version":7,"data":{"position":4}}'
SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$BOT_KEY" -binary | base64)
curl -sS -X POST "$SUPABASE_URL/functions/v1/engine/bot/action" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  --data "$(jq -n --arg p "$PAYLOAD" --arg s "$SIG" '{payload:$p, signature:$s}')"
```

### Inserting bot rows (Supabase dashboard — by hand, one-time)

There is no provisioning RPC; you `INSERT` directly. A `CHECK` enforces local ⇒
no webhook, server ⇒ webhook present.

```sql
-- local bot: no webhook, no secret — driven by the human's client
insert into bots (username, display_name, schema_version, is_local)
values ('easy_ai', 'Easy AI', 1, true);

-- server bot: webhook required; no stored secret — the bot's HMAC key is
-- derived from the master BOT_SIGNING_SECRET as HMAC-SHA256(secret, bot_id)
insert into bots (username, display_name, schema_version,
                  is_local, webhook_url, rated_eligible)
values ('hard_ai', 'Hard AI', 1,
        false, 'https://my-bot.example/wake', false)
returning id;  -- → <bot_id>; provision the bot with HMAC(BOT_SIGNING_SECRET, <bot_id>)
```

`schema_version` is the highest game schema the bot supports (mirrors the human
join gate — seating refuses a bot below the game's `schema_version`).
`rated_eligible = true` is required for a bot to enter a rated game. Set
`config` (jsonb) to parameterize a persona (N:1) and/or declare capabilities for
`botSeatable`. `config` is **public read-only reference data** —
`app_bots` exposes it for both local and server bots (the pickers and the
seatable filter read it), so never put secrets there.

### In-game, treat bots as players

Inside `buildContent` a bot seat is just a `GamePlayer` with
`type ==
ParticipantType.bot` — `info.username`/`displayName`/`avatarUrl`
resolve through the same `PlayersContext`. Don't branch on player type to
_render_ identity; use `GamePlayer.type` only when a rule needs it. The
`app_bots()` RPC (via `availableBotsProvider`) is for the **bot pickers** (solo,
waiting-room "Add bot") — not for in-game identity.

### Designing action data

"Action data" is **not** a bot concept — it is the move payload every player
already sends, and bots reuse it unchanged. The engine deliberately defines
**no** game-specific action type (mirroring observations: `parseObservation`
produces your own type, the engine never sees it). You own the shape, in three
places that must agree:

1. **Producer (human)** — your content widget builds the typed `ActionData` on a
   tap and submits it through the engine seam:
   `content.onAction(engine.serializeAction(action))`.
2. **Producer (local bot)** — `LocalBot.chooseAction` returns that **same typed
   `ActionData`**; the infra driver serialises it through the very same
   `engine.serializeAction`. A human tap and a bot decision are interchangeable.
3. **Consumer (server)** — your `applyAction` hook receives the resulting
   JSON as `p_data` (jsonb) and is the **only authority**: it validates legality
   and applies it. Never trust the client to have sent a legal move — a local
   bot's move has exactly the same untrusted provenance as a human's.

The action payload is a plain JSON object whose keys are yours to choose; keep
it minimal — it is **only** "what the move is". Infra supplies the seat
(`p_player_index`), version, RNG seed, config, and schema version to
`applyAction` as **separate parameters**, so never put them in the
payload. It is passed straight through as the hook's `p_data` with no infra
envelope; for the placeholder TicTacToe game that is literally
`{"position": 0–8}` (`(p_data->>'position')::INT`).

The engine gives you a **fully typed action seam**, the output mirror of
`parseObservation`: `BaseEngine` is generic over `TActionData`, your game
defines a Freezed `ActionData` (`fromJson`/`toJson`) alongside
`ObservationData`, and the engine's `serializeAction` is the **single** place a
typed action becomes JSON. Both Dart producers stay typed end to end and route
through it, so they cannot drift:

```dart
// the one action model
@freezed
abstract class ActionData with _$ActionData {
  const factory ActionData({required int position}) = _ActionData;
  factory ActionData.fromJson(Map<String, dynamic> json) =>
      _$ActionDataFromJson(json);
}

// engine — the only typed action → JSON step
@override
Map<String, dynamic> serializeAction(ActionData action) => action.toJson();

// human (content widget):  content.onAction(engine.serializeAction(action));
// local bot (chooseAction): return ActionData(position: best);  // engine serialises
// server bot (any language): emits the same JSON shape, e.g. {"position": best}
```

The seam stays typed inside Dart, but the **wire boundary** (what crosses to
`p_data`) is `Map<String, dynamic>` — that is exactly what reaches the hook. A
**server bot runs in another language, so it cannot share the Dart type**; its
uniformity is guaranteed at the JSON-shape level only. That makes
`applyAction` (the single consumer) plus the `action` Zod schema in your
`schemas` map the **one source of truth** that the Dart `ActionData` model and
the server bot both mirror — the edge function rejects (400) any action `data`
that fails the game's version `action` schema before your hook runs. Version
the shape by adding a `schemas` entry when it changes. See Hook 2
(`applyAction`) for the consumer contract.

---

## Timing Widgets

By default the game screen shows an infra-owned timing header above your content
widget:

- **Per-action mode** — `TurnCountdown`: a single shared "12m 34s" / "45s"
  countdown, error-red under 60 s.
- **Budget mode** — `BudgetClock`: a row of per-player "M:SS" cells, the active
  player's draining live.
- **Untimed** — nothing shown.

Most games need no extra work. If your game needs custom clock placement (e.g.
Chess showing each player's clock next to their captured pieces, or a 6-player
game only showing the active player's clock), use the headless builder widgets
directly.

> The fragments below assume you've pulled locals off the context in `build`, as
> in the content-widget template: `final timing = content.timing;`,
> `final pendingPlayers = content.frame.pendingPlayers;`,
> `final myPlayerIndex = content.myPlayerIndex;`.

### `TurnTimerBuilder` — per-action countdown

Owns a `Timer.periodic(1 s)`, ticks toward `deadline`, self-cancels at zero.
Passes the remaining `Duration` to your `builder` callback.

Pass `isPaused: true` to freeze the displayed value without cancelling the timer
— it resumes from the correct wall-clock position when `isPaused` returns to
`false`. Use this to stop the clock from visually counting down while the device
is offline. The infra-owned `TurnCountdown` shell does this automatically; you
must wire it yourself when using the headless builder.

Because `isOfflineProvider` is a Riverpod provider, your content widget must
extend `ConsumerWidget` (not `StatelessWidget`) to read it:

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

Owns a `Timer.periodic(1 s)`. For the active player it drains live using
`turnStartedAt`; for inactive players it shows the static bank value. Passes
`(int remainingMs, bool isActive)` to your `builder` callback.

`playerTimes` is 0-indexed by player index — the same scheme as
`pendingPlayers`. `playerTimes[myPlayerIndex]` is your bank; `playerTimes[i]` is
any player's bank.

Pass `isPaused: ref.watch(isOfflineProvider)` for the same reason as
`TurnTimerBuilder` — otherwise the bank appears to drain while the device is
offline. The infra-owned `BudgetClock` shell does this automatically.

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

When you provide custom timing display inside your content widget, the infra
header above the board is still visible. If you want to suppress it, that is a
future concern — for now, avoid duplicating the same clock in both places by not
watching the infra header's timing mode condition.

---

## Backend Changes Required

A game's server-side rules surface is **six TypeScript methods on a `GameEngine`**
— `initialState`, `applyAction`, `computeObservation`, plus optional `ratingPool`,
`handleEvent`, and `botSeatable`. They all live in the **`game` edge
function** as one typed object you export from `functions/_lib/game.ts` — see
**The game edge function** below. There is **no SQL to write for the rules**; the
gated `engine_*` RPCs the edge function commits through are infra and stay
untouched.

The engine's **backend** is **vendored** into your app — run
`dart run eigen_engine:sync_supabase` from the app directory. It copies the
engine's `migrations/*.sql`, the single `engine` edge function (its harness +
the shared `_engine` framework, serving the `game`, `social`, `internal`, and
`bot` route groups), and
`seed.sql` into your `supabase/`, leaving your app-owned files (any game
migration, your `functions/_lib/game.ts`) untouched. Ratings (OpenSkill) and push
notifications run inside the edge function now — there are no separate
`update-ratings` / `refresh-fcm-token` functions. Commit everything, then
`supabase db reset`. Re-run when you bump the engine version. See **Supabase
project setup** below for the one-time config.

You normally write **no game SQL at all**. (A migration is only needed if your
game adds its own tables; the rules themselves are pure TypeScript.)

### The game edge function

The rules run as TypeScript inside the engine-owned edge functions (the whole
`_engine/` framework — Hono routing, auth, gated reads/commits — is bundled in on
import). There are **four** functions — `game` (client JWT), `social` (client
JWT), `internal` (cron/webhook secret), `bot` (per-bot HMAC) — but you implement
only the `GameEngine`; the framework wires it into all of them. Ownership mirrors
the backend's vendoring rule:

| Path                                                            | Owner   | On `sync_supabase`                      |
| --------------------------------------------------------------- | ------- | --------------------------------------- |
| `functions/_engine/**`, `functions/_types/**`                   | engine  | re-vendored (overwritten + pruned)      |
| `functions/{game,social,internal,bot}/*` (`index.ts`, config…)  | engine  | re-vendored (overwritten + pruned)      |
| `functions/_lib/game.ts`                                        | **you** | scaffolded **once**, then never touched |

(`deno.lock` is git-ignored and regenerated per project, so it is never copied
or pruned — your local lockfile is left alone.)

So your entire server-side rules surface is one file — `game.ts` — which exports
a `GameEngine` instance: **Zod schemas per payload** (the `schemas` map) plus the
six methods. The schemas are the single source of truth — derive the payload
types from them with `z.infer` and the whole engine is typed end-to-end:

```ts
import { z } from "zod";
import { IllegalMoveError, passthroughObservation } from "engine/game-engine.ts";
import type {
  ApplyActionArgs,
  BotSeatableArgs,
  Envelope,
  EventArgs,
  GameEngine,
  InitialStateArgs,
  RatingPoolArgs,
} from "types/engine.types.ts";

const stateSchema = z.object({ board: z.array(z.number()).length(9) });
const actionSchema = z.object({ position: z.number().int().min(0).max(8) });
const configSchema = z.object({});

type State = z.infer<typeof stateSchema>;   // `type`, not `interface`
type Action = z.infer<typeof actionSchema>;
type Config = z.infer<typeof configSchema>;

class MyGame implements GameEngine<State, Action, Config> {
  readonly schemas = {
    1: { state: stateSchema, action: actionSchema, config: configSchema },
  };
  initialState(args: InitialStateArgs<Config>): Envelope<State> {/* … */}
  applyAction(
    args: ApplyActionArgs<State, Action, Config>,
  ): Envelope<State> {
    /* args.state / args.data are already parsed + typed — no casts.
       throw new IllegalMoveError("…") to reject; return the new envelope */
  }
  handleEvent(args: EventArgs<State, Config>): Envelope<State> {
    /* forfeit/timeout consequence */
  }
  computeObservation = passthroughObservation<State, Config>; // perfect-info
  ratingPool(args: RatingPoolArgs<Config>): string | null {
    return null; // unrated; return a pool name (e.g. "rapid") to rate
  }
  botSeatable(args: BotSeatableArgs<Config>): boolean {
    return true; // every bot seatable; tighten per your config
  }
}

export const gameEngine: GameEngine = new MyGame();
```

The `GameEngine` contract (the `Args` types, `Envelope`) is
defined in `functions/_types/engine.types.ts` — read it for the authoritative
signatures; `IllegalMoveError`, `passthroughObservation` (the perfect-info
default) and
the schema-boundary helpers live in `functions/_engine/game-engine.ts`.

**The harness enforces the schema boundary for you.** Each route first
validates the request body's *envelope* (ids, versions, timing fields) against
an engine-owned Zod schema — a malformed request 400s before any handler code
runs. Then, before any hook runs, the
framework picks the game row's `schema_version` entry from `schemas` and parses
every payload through it, so hook bodies never see unvalidated JSON:

| Payload                                | On schema failure                    |
| -------------------------------------- | ------------------------------------ |
| client `config` at create              | 400 (Zod issues in the message)      |
| client/bot action `data`               | 400                                  |
| `schema_version` not in `schemas` at create | 400                             |
| stored `state`/`config` on read        | 500 (corruption / missed version)    |
| loaded game's version not in `schemas` | 500 (EF deployed behind its data)    |
| hook-returned `state`                  | 500 (validated before every commit)  |

Client payloads flow onward **sanitized** — unknown keys stripped, defaults
applied — into your hooks, the `actions` log, and `games.config`. Two rules keep
this sound: keep schemas **transform-free** (what parses is what persists, and
hook output is re-validated against the same `state` schema), and derive payload
types as `type` aliases (an `interface` fails the engine's `JsonObject`
constraint).

**Schema versioning:** ship one `schemas` entry per `schema_version` you
support. On a breaking shape change, add a new entry — games created earlier
keep parsing under theirs — and make the payload type the tagged union of the
versions' shapes so hooks can narrow (`schemaVersion` also arrives in every
hook's args). This is the TS twin of the Dart side's
`BaseEngine.parseObservation` branching on its `schemaVersion` field.

`applyAction` rejects a rule-breaking move by throwing `IllegalMoveError`
(→ HTTP 400 with the message); any other throw is treated as a game bug (→ 500).
The
infra has already confirmed it is the acting seat's turn at the expected version
before calling, so do not re-check turn order. `ratingPool` and `botSeatable` need
**Dart twins** in your `GameModule` (the client gates the create-dialog
Rated/Casual toggle and the bot pickers locally); the server stays authoritative.
Seeds are 64-bit `bigint`; advance them via `_engine/prng.ts` for every random
value consumed and return the advanced `rng_seed`.

Iterate locally with `supabase functions serve` (or
`deno check
--config supabase/functions/engine/deno.json supabase/functions/engine/index.ts`
for a quick type-check). Because `game-engine.ts` has no Supabase/Deno runtime
dependency, your gameEngine is unit-testable in isolation. Deploy with
`supabase functions deploy engine`.

Once your app is in production, migrations become append-only and schema changes
must stay backward-compatible with app versions still in the wild — see
[README → Versioning & backward
compatibility](../README.md#versioning--backward-compatibility) (expand/contract,
mobile update lag, in-flight game state).

### Supabase project setup (one-time, per app)

The engine vendors the _content_ of the backend (migrations, functions, seed),
but each app owns its Supabase **project config** — `config.toml` is **never
vendored**, because it carries per-project values (your `project_id`) and the
engine must not clobber app-specific edits. Base yours on the engine's
`supabase/config.toml` (it's the reference) and keep the engine-required
settings in sync by hand when you bump the engine version:

1. **`config.toml`** — `supabase init` generates a default; base yours on the
   **engine's `supabase/config.toml`** and set your own `project_id`. Ensure the
   engine-required settings are present:
   - `[db.seed] sql_paths = ["./seed.sql"]`
   - `[auth] signing_keys_path = "./signing_keys.json"` and
     `[auth.external.google]` (`client_id`/`secret` from env)
   - For guest auth (see `engine_architecture.md` §25): set
     `[auth]
     enable_anonymous_sign_ins = true` and
     `enable_manual_linking = true` (the latter is required for the guest→Google
     upgrade). Enable the **same two settings in the production Supabase
     dashboard** (Authentication → Sign In / Providers → "Allow anonymous
     sign-ins", and → "Manual linking"). No deep-link or
     `additional_redirect_urls` change is needed — the upgrade uses native
     Google ID-token linking (`linkIdentityWithIdToken`), which reuses the app's
     existing native Google Sign-In and never opens a browser redirect.
   - `[edge_runtime]` + the **`[functions.engine]`** block
     (`verify_jwt = false` — auth is per route group *inside* the function:
     user JWT for `game`/`social`, secret API key for `internal`, per-bot HMAC
     for `bot`), with `import_map` / `entrypoint` pointing at
     `./functions/engine/` — copy it verbatim from the engine config. The block
     is what makes the function deployable; without it
     `supabase functions deploy`/`serve` won't pick it up.
2. **Vendor the backend:** `dart run eigen_engine:sync_supabase` (migrations +
   functions + seed), then commit. The first run scaffolds
   `functions/_lib/game.ts` and prints a reminder to add the
   `[functions.engine]` config block; implement your `gameEngine` in that file
   (see **The game edge function** above).
3. **`functions/.env.local`** — set the Firebase service-account vars
   (`FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`, `FIREBASE_PROJECT_ID`) and
   `BOT_SIGNING_SECRET` if you run server bots. This file is git-ignored.
4. **`signing_keys.json`** — local JWT signing keys; git-ignored and created by
   the Supabase CLI for local dev (see Supabase local-development docs). Not
   vendored.
5. `supabase start` → `supabase db reset` (applies migrations + `seed.sql`).
6. **Production:** deploy the edge functions and set their secrets — see the
   _Backend / Supabase Production Checklist_ near the end of this guide.

---

### Hook 0: `ratingPool(args: RatingPoolArgs<Config>): string | null`

Optional. Decides whether — and in which pool — a game with the chosen settings
is rated. Return a pool name (`'rapid'`, `'daily'`, …) or `null` for unrated.
`args` carries `access`, `turnSeconds`, `budgetSeconds`, `incrementSeconds`,
`minPlayers`, `maxPlayers`, `config`.

`rated` is a **validated assertion**, not a preference: the client computes it
from the **Dart twin** of this method (plus its guest status) and sends a concrete
`rated`. The edge function recomputes `canBeRated = pool != null && !guest` and
**rejects a mismatch** (422) rather than coercing. There is no *forced-rated* mode
— an ineligible config or a guest must send `rated = false`, and the create dialog
hides/forces the toggle accordingly. Pool names stay server-authoritative.

**Default**: `null` (all games unrated until overridden).

```ts
ratingPool(args: RatingPoolArgs<Config>): string | null {
  if (args.access !== "public") return null;     // only public games rate
  if (args.turnSeconds != null) return "rapid";  // map timing mode → pool
  if (args.budgetSeconds != null) return "daily";
  return null;                                    // untimed public ⇒ unrated
}
```

Keep a **Dart twin** in your `GameModule` with the identical rule so the New Game
dialog can show the live Rated/Casual badge and gate the toggle (hidden when the
pool is `null` or the user is a guest). The twin and this method must agree — the
server rejects the create if they don't.

---

### Hook 0b: `botSeatable(args: BotSeatableArgs<Config>): boolean`

Optional. Decides whether a bot may be seated into a game with the chosen config.
Called by the edge function before seating (the `add-bot` and `create-solo`
routes); return `true` to allow. `args` carries `botConfig` (the bot's declared
capabilities, from `bots.config` — opaque JSON, unversioned by your game
schemas) and `gameConfig` (`games.config`, already parsed against the game's
version config schema, so it arrives as your typed `Config`). It is the
**single source of truth** for config compatibility, and gates the variant axis
`schema_version` can't (a bot can match the schema but not the rules variant).

**Default**: `true` (every bot seatable). Override to gate by the capability keys
your game stores in `bots.config` — the engine imposes no schema on `bots.config`.

```ts
botSeatable(args: BotSeatableArgs<Config>): boolean {
  // Example: a chess bot lists supported variants in its config; default "standard".
  const variant = args.gameConfig.variant ?? "standard"; // typed Config
  const supported = (args.botConfig.variants as string[]) ?? ["standard"];
  return supported.includes(variant);
}
```

Keep a **Dart twin** in your `GameModule` so the bot pickers filter the cached
`app_bots` catalog by the same verdict — no client-side divergence, and the
client never offers an opponent that seating would reject.

---

### Hook 1: `initialState(args: InitialStateArgs<Config>): Envelope<State>`

`args`: `seed` (`bigint`), `playerCount`, plus the `HookContext` (`config` —
parsed and typed, `schemaVersion`). Returns the starting envelope — must include
`state`, `pending_players`, and `rng_seed`; may include `turn_seconds`. The
returned `state` is validated against the game's version `state` schema before
it is committed.

```ts
initialState(args: InitialStateArgs<Config>): Envelope<State> {
  // Consume setup randomness via _engine/prng.ts if needed (shuffle, deal),
  // then return the advanced seed.
  let seed = args.seed;
  return {
    state: { board: [], action_count: 0 },
    pending_players: [0],
    rng_seed: seed, // the (possibly advanced) seed — must be non-zero
    // turn_seconds: 60, // optional: override timing for the very first action only
  };
}
```

**Return envelope fields:**

| Field             | Required | Description                                                                                                                            |
| ----------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `state`           | yes      | Pure game payload. No whose-turn or winner info.                                                                                       |
| `pending_players` | yes      | 0-based indices that may act first.                                                                                                    |
| `rng_seed`        | yes      | The seed after consuming any setup randomness. **Must be non-zero** — infra raises if null or 0.                                       |
| `turn_seconds`    | no       | Fixed deadline for the first action only (overrides game-level timing for this action). Omit to use the game's configured timing mode. |

---

### Hook 2: `applyAction(args: ApplyActionArgs<State, Action, Config>): Envelope<State>`

`args`: `state`, `pending`, `data` (the move), `playerIndex`, `seed`, plus the
`HookContext`. `state`, `data`, and `config` arrive parsed against the game's
version schemas — a move whose `data` fails the `action` schema is rejected
with 400 before this hook runs, so validate **game-rule** legality only, not
shape. The infra has **already** confirmed it is this seat's turn at the
expected version under the lock, so do not re-check turn order either. Reject a
rule-breaking move by throwing `IllegalMoveError` (→ 400 with the message);
any other throw is a game bug (→ 500).

```ts
applyAction(
  args: ApplyActionArgs<State, Action, Config>,
): Envelope<State> {
  // 1. Validate the move is legal; reject if not.
  if (!isLegal(args.state, args.data, args.playerIndex)) {
    throw new IllegalMoveError("cell already occupied");
  }
  // 2. Apply it to produce the new state. 3. Consume randomness via
  //    _engine/prng.ts as needed, threading the advanced seed.
  // 4. Decide who acts next (empty ⇒ game over) and whether there is an outcome.
  const newState = /* … */ args.state;
  const ongoing = /* … */ true;
  return {
    state: newState,
    pending_players: ongoing ? [(args.playerIndex + 1) % 2] : [],
    rng_seed: args.seed, // advanced if randomness was consumed; non-zero
    ...(ongoing ? {} : { outcome: /* OutcomeEntry[] */ [] }),
  };
}
```

**Return envelope fields**:

| Field             | Required | Description                                                                                                                                                                                                |
| ----------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `state`           | yes      | Updated game payload.                                                                                                                                                                                      |
| `pending_players` | yes      | Who acts next. Empty array = game over.                                                                                                                                                                    |
| `rng_seed`        | yes      | The seed after consuming any randomness. **Must be non-zero.**                                                                                                                                             |
| `outcome`         | no       | **Omit when the game is ongoing** — an absent key is how infra knows play continues. Include on game end as an array of per-player results (see below).                                                    |
| `turn_seconds`    | no       | Fixed deadline for **this action only** — does not touch any player's budget bank. Use for phase-specific windows (Nope window, betting timer). Omit to let infra apply the game's configured timing mode. |

**`outcome` array format** (one entry per participant):

```json
[
  { "player_index": 0, "result": "win", "placement": 1, "team_index": 0 },
  { "player_index": 1, "result": "loss", "placement": 2, "team_index": 1 }
]
```

Required keys: `player_index` (int), `result` (`"win"` | `"loss"` | `"draw"` |
`"eliminated"`), `placement` (int, 1 = best, ties share the same value),
`team_index` (int, use `player_index` for individual games; teammates share a
value for team games). Optional: `"score"` (numeric). See
`engine_architecture.md §8` for team game and N-player examples.

**Mid-game player elimination** (Poker bust-out, Exploding Kittens explosion):
`game_outcomes` is only written once, when the game ends. Do not include
eliminated players in the `outcome` array until the game is truly over. Instead:

- Exclude eliminated players from all future `pending_players` returns.
- Record the elimination in `p_current_state` (e.g.
  `{"eliminated": [2], "placement": {"2": 4}}`).
- In `computeObservation`, put `{"is_eliminated": true, "placement": 4}`
  in the eliminated player's observation slice — the content widget uses this to
  show "You were eliminated" immediately.
- When the game ends, build the full `outcome` array including eliminated
  players with their correct `"placement"` values for ELO.

---

### Hook 2b: `handleEvent(args: EventArgs<State, Config>): Envelope<State>`

`args`: `state`, `pending`, `type`, `data` (a typed `EventData` union — no
casts needed), `seed`, plus the `HookContext`. Decides the consequence of a
system-initiated event. Unlike `applyAction` it **cannot be illegal** — it
always resolves to an envelope. The hook's `type` is only ever one of two
values (`data.type` additionally distinguishes an engine-driven
`'auto_forfeit'` from a voluntary resign):

| `type`      | Trigger                                                  | Which seat(s)                                                                   |
| ----------- | -------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `'timeout'` | the `expire` route (client nudge) or the cron sweep      | **all of `args.pending`** ran out of time — no `player_index` in `data`         |
| `'forfeit'` | the `forfeit` route (resign) or the account-deletion purge | `args.data.player_index` — the single target seat                              |

A `timeout` shares one deadline across all pending seats, so resolve the **whole
set at once** — you may declare a draw when everyone flags. A `forfeit` targets
one seat. Both return the same envelope as `applyAction` (`state`,
`pending_players`, `rng_seed`, optional `outcome`, optional `turn_seconds`).

```ts
handleEvent(args: EventArgs<State, Config>): Envelope<State> {
  if (args.data.type === "timeout") {
    // Every seat in args.pending timed out. Decide holistically: here, the
    // lone non-pending seat wins; if all seats are pending, it's a draw.
    const survivors = allSeats.filter((s) => !args.pending.includes(s));
    return survivors.length === 1
      ? winFor(args, survivors[0])     // single survivor wins
      : drawAmong(args, args.pending); // everyone flagged → draw
  }
  // forfeit / auto_forfeit: a single seat is out; the union narrows here.
  const loser = args.data.player_index;
  const winner = (loser + 1) % 2; // adjust for N>2 games
  return {
    state: args.state,
    pending_players: [],
    outcome: [
      { player_index: winner, result: "win",  placement: 1, team_index: winner },
      { player_index: loser,  result: "loss", placement: 2, team_index: loser },
    ],
    rng_seed: args.seed,
  };
}
```

A multiplayer forfeit (or a timeout that leaves the game live) might just advance
past the affected seats instead of ending the game:

```ts
// Skip: drop the timed-out seats from pending, game continues (some N-player games).
return {
  state: args.state,
  pending_players: [], // hook recomputes the next pending set
  rng_seed: args.seed,
};
```

---

### Hook 3: `computeObservation(args: ComputeObservationArgs<State, Config>): ObservationSlice`

`args`: `state`, `pending`, `playerIndex`, `participantCount`, `isReplay`, plus
the `HookContext`. The edge function fans this out once per participant after
every transition (and per historical version for replay). Returns
`{ data, pending_players }` — the slice `data` is deliberately schema-less
(`JsonObject`): it is an output-only projection the Dart client parses.
**Perfect-info games do not override this** — assign the
`passthroughObservation` default (the identity projection).

Override for hidden-info games to strip opponent cards/hands and optionally narrow
`pending_players`. Use `isReplay` to reveal information post-game (e.g. all hole
cards in a Poker replay).

```ts
// Perfect-info: assign the helper, instantiated with your payload types.
computeObservation = passthroughObservation<State, Config>;

// Hidden-info: override.
computeObservation(args: ComputeObservationArgs<State, Config>): ObservationSlice {
  if (args.isReplay) {
    // Finished game: reveal everything for review.
    return { data: args.state, pending_players: args.pending };
  }
  // Live: strip every seat's private info except args.playerIndex, and
  // optionally narrow the pending set this seat is allowed to see.
  return {
    data: stripOpponentHands(args.state, args.playerIndex),
    pending_players: args.pending,
  };
}
```

`isReplay` is `true` **only** when projecting a finished game for replay, so the
live fan-out always passes `false`.

---

## Timing and the Hook Contract

Infra owns all clock logic. The hooks interact with timing through a single
optional field: `turn_seconds`.

### How timing works end-to-end

**At game creation**, the host selects a timing mode (the `game/create` route).
These are mutually exclusive — you cannot set both `turn_seconds` and
`budget_seconds`.

**After each action**, infra applies the deadline precedence chain (see
`engine_architecture.md §3`).

**When the hook returns `turn_seconds`**, infra uses that as the deadline for
this action only and does not touch any player's bank. Use this for
phase-specific windows regardless of the game's overall timing mode.

**In budget mode**, bank deduction happens automatically — the hook does not
implement it. The hook only needs to handle the consequence of a timeout action,
not the clock itself.

**When time expires**, infra calls `handleEvent` with `type = 'timeout'`.
The client-side `game/expire` route nudges the server immediately when a client
detects the deadline — the cron sweep is just a backstop. Any active participant
can call it safely; the server validates under lock.

> **Budget mode constraint:** budget mode must only be used in games where at
> most one player is pending at any given time. If your game has phases where
> multiple players are pending simultaneously, use `turn_seconds` for those
> phases. See `engine_architecture.md §3` for the full reasoning.

---

## Entry Points Reference (Infra — Do Not Modify)

You don't call these directly — the engine's repositories do — but it helps to
know the surface. There are two tiers (full detail in `engine_architecture.md`
§5):

**Edge-function routes** (the client calls these; each runs the rules in TS and
commits through a gated `engine_*` RPC):

| Route | Purpose |
| ----- | ------- |
| `game/create` · `game/create-solo` | Create a game / a sole-human "vs AI" game. The EF validates timing + players, gates guests, derives the pool (`ratingPool`), and **validates the client's `rated` assertion**. |
| `game/start` | `initialState` → writes `game_states` v0 + observations, inits banks, marks `active`. |
| `game/action` | The move: runs `applyAction`, commits under the row lock (version + deadline + pending checks), fans out observations, writes outcome/ratings on finish. |
| `game/forfeit` · `game/expire` | `handleEvent('forfeit')` / `('timeout')`. `expire` is the client deadline nudge (cron is the backstop). |
| `game/add-bot` · `game/local-bot-action` | Seat a server bot (host) / drive a local bot seat. |
| `game/replay` | The caller's observation slice at every version (finished, participant-only), projected through `computeObservation` (`isReplay = true`). |
| `game/delete-account` | Account teardown (forfeits active games, then purges). |
| `social/friend-request` · `social/accept` · `social/remove` | Friend writes; the EF gates the caller and pushes the notification. |

**Client-direct RPCs** (the client calls these straight over PostgREST under
RLS): `app_join_game` / `app_join_game_by_code`, `app_cancel_game`, `app_leave_game`,
`app_lobby_games`, `app_friends_games`, `app_search_users`, `app_local_bot_observation`,
`app_bots`, `app_players`, `app_update_username`.

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
4. For budget mode: confirm `player_times` updates after each move and
   `turn_deadline` reflects the next player's bank.
5. Trigger a timeout: let the deadline pass without acting, confirm the cron
   sweep (`cron_expire_turns` → `internal/expire`) commits the timeout, and
   confirm the hook's timeout consequence is applied.
6. Test forfeit: click forfeit in the game screen, confirm `handleEvent`
   runs with a `{ type: 'forfeit' }` action, and confirm `game_outcomes`
   reflect the expected result.
7. Test leave: join as a non-host, call `app_leave_game`, confirm participant is
   removed and game status transitions correctly.
8. Test join-by-code: create a private/friends game, note the `short_code`
   displayed in the pre-game waiting room, join from another account using the
   code via the home screen's "Join via Code" dialog. If `APP_HOST` is
   configured, a QR code for the invite deep link is also shown — scan it with
   the second device to verify the deep link opens the join flow directly.
9. Test friends access: create a `friends` access game, confirm a non-friend
   cannot join, add friend, confirm friend can then join.
10. Test the rated assertion: create a public Rapid game with `rated: true` →
    `games.rated = true`, `games.rating_pool = 'rapid'`. Create an untimed public
    game → `games.rated = false`, `games.rating_pool = null`. Send `rated: true`
    for an ineligible game (null pool, or as a guest) → the `game/create` route
    rejects it **422 mismatch** (the EF validates, it never silently coerces).
11. Test rating update: play a rated game to completion → `player_ratings` rows
    created/updated, `rating_history` rows inserted for each player. Ratings are
    computed in the EF and written **in the same finishing transaction** — no
    external function or config is involved.
12. Test idempotency: a finishing commit that references an already-rated game
    `game_id` has its `rating_history` insert rejected by the unique indexes, so
    no duplicate rows are created and ratings are not double-applied.
13. `flutter analyze` → zero errors.

---

## Domain Configuration

### What `APP_HOST` Controls

`APP_HOST` in your app's `.env` is the authoritative source for the game's
subdomain (e.g. `mygame.example.com`). The app reads it via `Env.appHost` (your
app's `lib/env/env.dart`), passes it into `EngineConfig.appHost`, and the
framework generates invite links from `appConfigProvider`.

When `APP_HOST` is set, the pre-game waiting room automatically shows a QR code
(via `qr_flutter`) encoding the invite deep link
(`https://<APP_HOST>/join/<short_code>`), alongside the copy-code and share-link
buttons. When `APP_HOST` is not set, the QR code and share button are both
hidden.

However, Android and iOS verify domain ownership at **install time** by fetching
files from the host. Their configs are compiled into the app binary — they
cannot be changed at runtime. This means the host is declared in **four places**
that must always be kept in sync.

### What `LEGAL_HOST` Controls

`LEGAL_HOST` in your app's `.env` is the root domain where the terms of service
and privacy policy pages are hosted (e.g. `example.com`). The app reads it via
`Env.legalHost`, passes it into `EngineConfig.legalHost`, and the settings
screen builds terms/privacy links via `legalPageUrl()`
(`lib/core/utils/deep_links.dart`).

This is intentionally **separate from `APP_HOST`** for a critical reason: the
App Links / Universal Links deep link configuration only covers `APP_HOST` (the
game subdomain). If the terms and privacy URLs were built on `APP_HOST`, the OS
would intercept them as deep links and route them back into the app rather than
opening them in the browser. By using the root domain, which has no deep link
configuration, the in-app browser opens them directly.

The terms/privacy tiles in the settings screen are conditionally shown — they
only appear when `LEGAL_HOST` is set. Add it to `.env`:

```
LEGAL_HOST=eigeninteractive.com
```

Then add `LEGAL_HOST` as a GitHub Actions secret (repo Settings → Secrets →
Actions) and ensure the CI workflow writes it to `.env` (already done in
`android.yml`).

### The Four Places to Update

When the domain changes (e.g. from `mygame.example.com` to
`newgame.example.com`), update all four of the following atomically:

#### 1. `.env`

```
APP_HOST=mygame.eigeninteractive.com
```

This drives `gameInviteLink()` at runtime. After changing, re-run the envied
code generator:

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

Android fetches `https://<host>/.well-known/assetlinks.json` at install time to
verify this filter. If the host here doesn't match the deployed
`assetlinks.json`, App Links silently falls back to the browser.

> **Do not remove** `android:enableOnBackInvokedCallback="true"` from the
> `<activity>` element when editing this file. That flag opts the app into the
> Android 14+ predictive back gesture API. Its absence silently disables
> predictive back for all users on Android 14+.

#### 3. `ios/Runner/Runner.entitlements`

Change the `applinks:` value:

```xml
<array>
    <string>applinks:mygame.eigeninteractive.com</string>
</array>
```

iOS fetches `https://<host>/.well-known/apple-app-site-association` via Apple's
CDN at install time.

**Xcode step (required):** After editing this file, open Xcode → select the
Runner target → Signing & Capabilities → verify Associated Domains lists
`applinks:mygame.eigeninteractive.com`. If the entry is stale or missing, remove
it and re-add it. The entitlement file alone is not enough — it must be wired
into the Xcode project.

#### 4. `src/games.ts` in the Cloudflare Worker repo

The key in the `games` map is the subdomain prefix. To rename a game's
subdomain, update the key and re-deploy:

```typescript
export const games: Record<string, GameConfig> = {
  mygame: { // was: strategy
    name: "My Game",
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

- **Android and iOS changes require a new app release** — the host is baked into
  the binary at build time. Users on old builds will not have deep link
  interception for the new domain.
- **Cloudflare Worker changes take effect immediately** after `wrangler deploy`.
  If you change the subdomain, the old subdomain stops working immediately.
  Coordinate the Worker deploy with the app release.

### Verification After Changing the Domain

After deploying the Worker and before submitting the app to the stores, confirm
the verification files are correct:

- **Android:**
  [Google Digital Asset Links validator](https://developers.google.com/digital-asset-links/tools/generator)
  — paste the new domain and package name; it fetches and validates
  `assetlinks.json`.
- **iOS:** [AASA validator](https://yurl.chayev.com/) — paste the new domain; it
  fetches and validates `apple-app-site-association`.

Common failure causes:

- SHA-256 fingerprint in `assetlinks.json` doesn't match the signing keystore —
  re-run `keytool` and compare.
- iOS Team ID mismatch — find it at
  [developer.apple.com/account](https://developer.apple.com/account) under
  Membership.
- The verification file is served with a redirect — Cloudflare's orange cloud
  must be on and the Worker must not redirect `/.well-known/*` paths.

---

## Splash Screen Assets

The splash screen is **infra-owned**. Game implementors do not call
`FlutterNativeSplash.remove()` or touch `AppStartup` — the remove is driven by
`authStateChangesProvider.future` in `lib/core/startup/app_startup.dart` and
fires as soon as Supabase emits `INITIAL_SESSION`. See
`engine_architecture.md §13` for the full architecture, sequence diagram, and
generated file inventory.

When deploying a new game app, provide the logo assets and regenerate the
platform files.

### Asset Files to Create

Place in `assets/splash/` and declare the folder in `pubspec.yaml` under
`flutter: assets:`.

| File                          | Size               | Notes                                                                                                                                                        |
| ----------------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `assets/splash/logo.png`      | **1152 × 1152 px** | Light-mode logo. Keep artwork within the inner **640 px** — the outer ring is cropped on Android 12's circular icon mask. PNG with transparency recommended. |
| `assets/splash/logo_dark.png` | **1152 × 1152 px** | Dark-mode logo (white/light version for the dark `#141218` background).                                                                                      |

Optional:

| File                              | Size          | Notes                                                                                                             |
| --------------------------------- | ------------- | ----------------------------------------------------------------------------------------------------------------- |
| `assets/splash/branding.png`      | ≥ 600 px wide | Studio name / tagline shown at screen bottom. Add `branding:` and `branding_bottom_padding:` to the config block. |
| `assets/splash/branding_dark.png` | ≥ 600 px wide | Dark variant of branding image.                                                                                   |

### `pubspec.yaml` — add `image:` fields once assets exist

The `flutter_native_splash:` block already configures background colors. Add the
image lines when the assets are ready:

```yaml
flutter_native_splash:
  color: "#FFFBFF"
  color_dark: "#141218"
  image: assets/splash/logo.png # add this
  image_dark: assets/splash/logo_dark.png # add this

  android_12:
    color: "#FFFBFF"
    color_dark: "#141218"
    image: assets/splash/logo.png # add this
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
- [ ] Add `image:` / `image_dark:` to both the root and `android_12:` config
      blocks
- [ ] Run `dart run flutter_native_splash:create`
- [ ] Verify on a physical device: logo appears on the splash, splash disappears
      after auth resolves (not on a fixed timer), both light and dark OS themes
      show the correct logo variant

---

## In-App Review

In-app review is **infra-owned**. Game implementors do not call `ReviewNotifier`
or import `review_notifier.dart` — the win trigger fires automatically from
`game_screen.dart` whenever the local player's `OutcomeResult` is `win`.

The prompt appears every 5 wins (lifetime, persisted across sessions). The OS
silently enforces its own quota (3× per year on both platforms). All wins count
— game type, timing mode, and rated status are irrelevant.

See `engine_architecture.md §15` for the full architecture and the
`ReviewNotifier` source.

---

## In-App Updates (Android)

In-app updates are **infra-owned**. Game implementors do not touch
`UpdateNotifier` or the update lifecycle — everything is driven automatically
from `AppStartup` and `ShellScaffold`.

- **Immediate update** — full-screen system UI; skipped during active games and
  retried on the next resume.
- **Flexible update** — background download; `ShellScaffold` shows a snackbar
  with a "Restart" action when ready.

See `engine_architecture.md §15` for the full architecture and decision log.

---

## Analytics & Push Notifications

Both are **infra-owned**. Game implementors do not import
`analytics_service.dart`, `firebase_notification_service.dart`, or any Firebase
package — all events and notifications fire automatically from core
infrastructure.

**Android notification icon:**
`android/app/src/main/res/drawable/ic_notification.xml` is the one file in this
area that is **not** fully infra-owned. It contains a monochrome silhouette of
the app logo used for Android notification icons (API 21+ requires this — the
full-colour launcher icon renders as a white box). When deploying a new game,
replace this vector with one matching the new app's brand. See
`engine_architecture.md §20` for the three places it is referenced and the
rationale.

### Analytics events

| Event                 | When it fires                                |
| --------------------- | -------------------------------------------- |
| `game_created`        | After the New Game dialog creates the game   |
| `game_started`        | When the game transitions to `active` status |
| `game_finished`       | When outcomes arrive for the finished game   |
| `forfeit`             | After a forfeit RPC call succeeds            |
| `join_by_code`        | After joining by code succeeds               |
| `friend_request_sent` | After sending a friend request succeeds      |
| `friend_accepted`     | After accepting a friend request succeeds    |

### Push notifications sent automatically

| Title                          | Body                | Trigger                                                                                                                      |
| ------------------------------ | ------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| "Your turn"                    | "It's your move."   | `observations` INSERT or UPDATE where the user's player index enters `pending_players` (INSERT covers the game's first move) |
| "{creator} started a game"     | "Join now to play." | A `friends`-access game is created by an accepted friend (public games are lobby-discoverable, not pushed)                   |
| "{sender} wants to be friends" | "Tap to respond."   | A friend request is sent to the user                                                                                         |

### Setup

Firebase is mandatory. The following files are generated by
`flutterfire configure` and are **gitignored** — they are instance-specific and
must not be committed:

| File                                  | Platform                                         |
| ------------------------------------- | ------------------------------------------------ |
| `lib/firebase_options.dart`           | Dart (all platforms)                             |
| `android/app/google-services.json`    | Android native                                   |
| `ios/Runner/GoogleService-Info.plist` | iOS native                                       |
| `firebase.json`                       | FlutterFire CLI metadata only — not needed in CI |

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

See `engine_architecture.md §14` (analytics), `engine_architecture.md §18`
(obfuscation and symbol upload), and `engine_architecture.md §20` (push
notifications) for the full implementation, CI workflow details, and required
Vault secrets.

---

## Haptic Feedback

Haptic feedback is **infra-owned**. Game implementors do not import
`flutter/services.dart` or call `HapticFeedback` directly — all three moments
fire automatically from `game_screen.dart`.

| Moment                 | Haptic           | Trigger                                                            |
| ---------------------- | ---------------- | ------------------------------------------------------------------ |
| Valid action submitted | `lightImpact`    | Fires in `_submitAction` before the RPC call                       |
| Win outcome arrives    | `heavyImpact`    | Fires in `_onGameOutcomes` when the local player's result is `win` |
| Invalid move attempted | `selectionClick` | Fires via the `onInvalidAction` callback (see below)               |

### The `onInvalidAction` Callback

`buildContent()` receives `onInvalidAction: VoidCallback`. Call it in the
rejection branch of your tap handler — infra decides the haptic:

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

Pass it through from `GameModule.buildContent()` to your content widget as a
required field, exactly as shown in the content widget template above.

See `engine_architecture.md §16` for the full deduplication logic and file
inventory.

## External Console Setup

Steps required in external dashboards before the backend checklist can be
completed. Do these once per deployment.

### 1. Firebase Console

1. Go to [console.firebase.google.com](https://console.firebase.google.com) →
   **Create a project** (enable Google Analytics during setup).
2. Run `flutterfire configure` — it registers the Android and iOS apps inside
   your project automatically. You do not need to add apps manually in the
   console.
3. **Add SHA fingerprints** to the Android app (required for Google Sign-In on
   Android — `flutterfire` does not add these):
   - Firebase Console → Android app → **SHA certificate fingerprints** → add
     debug + upload fingerprints.
   - See [§SHA Fingerprints](#sha-fingerprints-for-android) below for the
     `keytool` commands.
4. Enable **Crashlytics**: Build → Crashlytics → Get started.
5. Verify **Cloud Messaging** is enabled: Project Settings → Cloud Messaging.
6. **Create a service account** for edge functions:
   - Project Settings → Service Accounts → **Generate new private key**.
   - Open the downloaded JSON and copy `client_email` → `FIREBASE_CLIENT_EMAIL`
     and `private_key` → `FIREBASE_PRIVATE_KEY`. Delete the file — only these
     two fields are needed.

### 2. Google Cloud Console — OAuth

Firebase auto-creates a paired Google Cloud project. Open it from Firebase
Console → Project Settings → the Google Cloud Console link.

1. **Configure the OAuth consent screen**: APIs & Services → OAuth consent
   screen.
   - User type: External (or Internal for internal testing).
   - Fill in app name, support email, developer contact, and authorized domains
     (`<ref>.supabase.co` and your app domain).
2. **Create a Web OAuth client**: APIs & Services → Credentials → Create
   credentials → OAuth client ID.
   - Application type: **Web application**.
   - Authorized redirect URI:
     `https://<supabase-project-ref>.supabase.co/auth/v1/callback`.
   - Note the **Client ID** and **Client Secret** — both go into Supabase Auth →
     Providers → Google.

> Android and iOS OAuth clients are created automatically when you register apps
> in Firebase Console. The Web client is the one Supabase needs for the
> server-side OAuth flow.

### 3. Supabase Auth — Google Provider

Supabase Dashboard → Authentication → Providers → **Google**:

- Enable the provider.
- **Client ID (from Google Cloud Console)**: the Web OAuth Client ID from
  step 2.
- **Client Secret**: the Web OAuth Client Secret from step 2.

Authentication → URL Configuration → **Redirect URLs** → add your deep link
scheme, e.g. `com.eigeninteractive.strategy://` (required for the native OAuth
callback).

### 4. APNs — iOS Push Notifications

Required before FCM can deliver push notifications on iOS.

1. [developer.apple.com](https://developer.apple.com) → Certificates,
   Identifiers & Profiles → **Keys** → create a key with **Apple Push
   Notifications service (APNs)** enabled.
2. Download the `.p8` file (only available once). Note the **Key ID** and **Team
   ID** (Membership page).
3. Firebase Console → Project Settings → Cloud Messaging → **Apple app
   configuration** → upload the `.p8` file with the Key ID and Team ID.

### SHA Fingerprints for Android

Firebase Console requires SHA-1 (and optionally SHA-256) of every certificate
that signs the app, because Google Sign-In validates the calling app's
certificate at runtime.

**Step 1 — Add the debug key now** (lets you test Sign-In in local dev builds):

```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey \
  -storepass android -keypass android
```

Copy the SHA-1 (and SHA-256) into Firebase Console → Android app → SHA
certificate fingerprints.

**Step 2 — Add the Play Store app signing key after your first upload**
(required for Sign-In to work for users who installed from the store):

Play App Signing is mandatory for new apps. Google re-signs your upload APK/AAB
with their own key before distributing it, so the app on users' devices is
signed with Google's key — not yours. If you only add your upload key's SHA,
Sign-In will fail in production.

After your first Play Store upload:

1. Google Play Console → your app → Release → Setup → **App signing**
2. Under **App signing key certificate**, copy the SHA-1 and SHA-256.
3. Add both to Firebase Console → Android app → SHA certificate fingerprints.

Your upload keystore SHA is optional — only needed if you test a locally-signed
release APK before uploading.

---

## Backend / Supabase Production Checklist

**External console (complete before `flutterfire configure`):**

- [ ] Firebase project created with Google Analytics enabled
- [ ] `flutterfire configure` run — registers Android and iOS apps automatically
- [ ] Debug keystore SHA-1 added to Firebase Console → Android app → SHA
      certificate fingerprints (enables Sign-In in dev builds)
- [ ] **After first Play Store upload:** Play Store app signing key SHA-1 and
      SHA-256 added to Firebase Console (Google Play Console → Release → Setup →
      App signing → App signing key certificate) — required for Sign-In to work
      for store installs
- [ ] Crashlytics enabled (Build → Crashlytics → Get started)
- [ ] Firebase service account key generated (Project Settings → Service
      Accounts → Generate new private key) — `client_email` →
      `FIREBASE_CLIENT_EMAIL`, `private_key` → `FIREBASE_PRIVATE_KEY`, file
      deleted
- [ ] OAuth consent screen configured in Google Cloud Console
- [ ] Web OAuth 2.0 client created with Supabase redirect URI
      (`https://<ref>.supabase.co/auth/v1/callback`)
- [ ] Supabase Auth → Providers → Google enabled with Web Client ID and Client
      Secret
- [ ] Supabase Auth → Sign In / Providers → **Allow anonymous sign-ins** enabled
      (guest play — see `engine_architecture.md §25`)
- [ ] Supabase Auth → Sign In / Providers → **Manual linking** enabled (required
      for the guest→Google upgrade; no redirect URL needed — native ID-token
      linking)
- [ ] Supabase Auth → URL Configuration → Redirect URLs includes the app's deep
      link scheme
- [ ] APNs key created in Apple Developer Console and uploaded to Firebase
      Console → Cloud Messaging (iOS)

**Backend:**

- [ ] `expire_all_turns` pg_cron job confirmed active in production (check
      Dashboard → Database → Cron Jobs)
- [ ] `serverless_base_url` set in `private.app_config` for production project
- [ ] `secret_api_key` created in Supabase Vault for production project,
      holding the project's **secret API key** (`sb_secret_…`) — the cron
      sweeps send it as the `apikey` header to `/engine/internal/*`, where
      `@supabase/server`'s `auth: 'secret'` mode validates it (no bespoke
      webhook secret exists)
- [ ] function secrets set via `supabase secrets set` (see
      `engine_architecture.md §21`): `BOT_SIGNING_SECRET`
      (server-bot HMAC key derivation), and `FIREBASE_CLIENT_EMAIL`
      / `FIREBASE_PRIVATE_KEY` / `FIREBASE_PROJECT_ID` (FCM push — the EF mints its
      own OAuth token). The `SUPABASE_*` vars are injected automatically.
- [ ] `[functions.engine]` block (`verify_jwt = false`) present in
      `config.toml` (per-app, not vendored) so the function deploys
- [ ] `supabase functions deploy engine` run — see
      `engine_architecture.md §21`. Ratings (OpenSkill) and notifications (FCM)
      run inside the shared framework; there is no `update-ratings` or
      `refresh-fcm-token` function or FCM-token cron job.
- [ ] Run `flutterfire configure` (Android + iOS) to generate
      `lib/firebase_options.dart`, `android/app/google-services.json`, and
      `ios/Runner/GoogleService-Info.plist` — all gitignored, do not commit
- [ ] Base64-encode the three files and add as GitHub Actions secrets:
      `FIREBASE_OPTIONS_DART_BASE64`, `GOOGLE_SERVICES_JSON_BASE64`,
      `GOOGLE_SERVICE_INFO_PLIST_BASE64`
- [ ] Replace `android/app/src/main/res/drawable/ic_notification.xml` with a
      monochrome silhouette of the new app's launcher icon foreground (Android
      API 21+ renders the full-colour launcher icon as a solid white box)
- [ ] Add `LEGAL_HOST` as a GitHub Actions secret (e.g. `eigeninteractive.com`)
      — controls the terms/privacy links in the settings screen
- [ ] PITR (Point-in-Time Recovery) enabled on Supabase Pro — `game_states` is
      append-only history, losing data affects rated game audit trail
- [ ] Rate limiting enabled on the `game/action` and `game/create` routes
      (Supabase Dashboard → Edge Functions, or an upstream gateway)
- [ ] Supavisor connection pooler: use **session mode** for the commit RPCs
      (`engine_commit_action` and the expire sweep, which use `FOR UPDATE`);
      transaction mode for read RPCs
- [ ] Realtime enabled only on tables that need it (`observations`, `games`,
      `relationships`) — disable on others to reduce noise
- [ ] Row-level security verified on all tables (run
      `SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public'`)

---

## Shipping the App (Android / Google Play)

Store packaging and release are **app-owned** (the engine has no app to ship).
The reference setup lives in the `strategy` app — copy it for a new game:

- **`fastlane/`** — `Fastfile` with `android internal` / `android production`
  lanes (`upload_to_play_store` with the built AAB) and `Appfile` (the
  `package_name`), plus a `Gemfile` for the `fastlane` gem.
- **CI** (`.github/workflows/android.yml`) — the `build` job builds a **signed,
  obfuscated release AAB**
  (`flutter build appbundle --release --obfuscate
  --split-debug-info=…`), and
  the `deploy` job runs `bundle exec fastlane android
  internal` to push it to
  the Play internal track.

Per-app setup:

- Create an upload keystore; add `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
  `KEY_ALIAS`, `KEY_PASSWORD` as GitHub Actions secrets (CI writes
  `android/key.properties` from them).
- Create a Google Play service account with the _Release_ permission; add its
  JSON as `GOOGLE_PLAY_JSON_KEY` (used by fastlane `upload_to_play_store`).
- `applicationId` (Android) / bundle id (iOS) are the app's own store identity —
  set them per product (not derived from the engine).
- First upload must be done manually in the Play Console (to create the app
  listing); subsequent releases flow through fastlane.

iOS store submission (TestFlight/App Store) is not yet wired in the reference
app; add an `ios` fastlane lane when you target iOS.
