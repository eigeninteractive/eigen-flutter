# Game Implementation Guide

This guide explains how to implement a new game using the **Eigen Engine**.

---

## Overview

Eigen Engine is a **whitelabel game engine** — the core infrastructure (auth,
networking, real-time updates, timing) is shared, while each game provides its
own rules and UI through two same-shaped containers, one per language:

- a **TypeScript `GameModule`** — a registry of **`GameRules` units keyed by
  `schema_version`**. Each unit bundles the Zod payload schemas plus six hooks
  (three core: `initialState`, `applyAction`, `computeObservation`; three
  optional: `ratingPool`, `applyLifecycle`, `botSeatable`) that the engine's edge
  function runs server-side (see **Backend Changes Required**), and
- a **Dart `GameModule`** — a registry of **client-side `GameRules` units keyed
  by the same versions** (payload codec + `isValidAction` legality, board
  rendering, local bots, and display-only twins of
  `ratingPool`/`botSeatable`), plus the version-independent creation/about UI.

**A version is a self-contained unit and the framework owns all dispatch**:
every request/screen resolves the game row's `schema_version` entry and uses
that unit — game code never branches on version. Shipping a breaking change
means adding a `v2` unit on both sides (reusing unchanged pieces from `v1` by
import), not editing `v1` (see **Shipping a new schema version**).

The authoritative signatures are the `GameRules`/`GameModule` interfaces in
`supabase/functions/_types/engine.types.ts` and the Dart
`GameRules`/`GameModule` classes in `lib/core/game/game_module.dart` — the
same two names mean the same two concepts in both languages.

### Shared vocabulary (both languages use exactly these names)

Everything that exists on both sides is textually parallel — same unit name
(`GameRules`), same args-object names (`RatingPoolArgs`, `BotSeatableArgs`),
same field names — so porting logic between the twins is transcription, not
translation. The identifiers:

| Term            | Meaning                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------- |
| `state`         | The authoritative pure game payload (`game_states.state`). Server-side only.                |
| observation     | One seat's projected view of the state — what the Dart client parses and renders.           |
| `data`          | One action's payload, as submitted (and as logged in `actions`).                            |
| `pending`       | 0-based seat indices that may act next. Empty ⇒ game over.                                  |
| `playerIndex`   | The 0-based seat of the acting/viewing player.                                              |
| `config`        | The per-instance creation config (`games.config`).                                          |
| envelope        | A hook's return: `{ state, pending_players, outcome?, turn_seconds? }`.                     |
| `outcome`       | Per-seat results written to `game_outcomes` when the game ends.                             |
| `cause`         | The transition that produced a state: a move, an event, or null for the initial frame.      |

Which hooks live where:

| Hook / member                            | TS `GameRules` (authoritative)   | Dart `GameRules` (client)             |
| ---------------------------------------- | -------------------------------- | ------------------------------------- |
| `initialState`, `applyAction`, `applyLifecycle`, `computeObservation` | ✅ the rules | — (client consumes observations)      |
| `ratingPool`, `botSeatable`              | ✅ enforced                      | ✅ display-only twin — keep in sync   |
| `schemas` (Zod payload contracts)        | ✅                               | ✅ as the codec: `parseConfig` / `parseObservation` / `parseAction` / `serializeAction` (Freezed) |
| `buildContent`, `localBots`              | —                                | ✅ client-only                        |
| `isValidAction`                          | — (`applyAction` is the check)   | ✅ UX-only transcription of its legality half |
| `previewAction`                          | — (`applyAction` is the truth)   | ✅ required; the game's own optimistic projection (return null = server-driven). Infra never calls it |

Every "keep in sync" in this table is enforceable, not aspirational: shared
JSON fixtures run against **both** units and fail a test on divergence — see
[Twin-drift fixtures](#twin-drift-fixtures) under Testing Your Game.

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
│       ├── game_module.dart      # the GameModule: versions map + creation UI
│       └── v1/                   # one folder per schema_version
│           ├── rules.dart        # the v1 GameRules: codec + isValidAction + wiring
│           ├── data/models/game_models.dart  # ObservationData, ActionData, GameConfigData (Freezed)
│           └── presentation/{my_game_board,my_game_content}.dart
└── supabase/                     # config.toml + migrations + functions/_lib/
                                  #   game.ts (the GameModule versions map) +
                                  #   game/v1.ts (the v1 GameRules — TS unit)
```

The `v1/` folders are a **convention, not enforced** — the contract is the
`versions` map, and the compiler checks that. But mirroring the layout across
the two languages is what makes a version bump mechanical: `v2` is a new folder
in both trees plus one new map entry on each side.

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
> board/action shape is breaking and ships as a **new version unit** (a `v2/`
> folder + map entry on both sides), never an in-place edit of `v1/`. See
> **Shipping a new schema version** below and
> [`engine_architecture.md`](engine_architecture.md) §24 (Backward
> Compatibility).

---

### 2. Game Rules (`v1/rules.dart`)

The Dart `GameRules` is the **client half of one schema version**, the twin of
your `_lib/game/v1.ts`. It is a stateless unit (like the TS one) responsible
for:

- the **payload codec** — `parseConfig` / `parseObservation` / `parseAction` /
  `serializeAction`, one Freezed delegation each. This is the Dart mirror of
  the TS unit's `schemas`.
- `isValidAction` — local legality check for UX feedback only. Authoritative
  validation happens server-side in the TS `applyAction`. Its named parameters
  (`obs`, `pending`, `data`, `playerIndex`, `config`) deliberately match the
  TS `ApplyActionArgs` fields: writing it is transcribing the legality half of
  your TS `applyAction`.
- `previewAction` — the actor's own optimistic projection of the TS
  `applyAction` onto this seat's observation (see **Instant feedback**
  below). Infra never calls it; it standardizes where prediction logic
  lives. Return null (always correct) when a move's outcome depends on
  hidden information — or for every move, if the game is purely
  server-driven.
- `buildContent` and `localBots` — rendering and client bots (steps 3–5).
- the display-only twins `ratingPool` / `botSeatable`.
- pure rendering helpers you add (e.g., "which cells form the winning line") —
  they live on your subclass; widgets receive the typed unit.

A unit belongs to exactly one `schema_version` and parses exactly one
generation of shapes, so it never branches on version. There is no
per-game-instance object: the parsed config is passed in where needed (as in
TS, where every hook receives `config` in its args).

Player counts are declared on `GameCreationSpec`, and player identities arrive
via `PlayersContext` — the rules unit carries no player metadata.

Turn-gating, game-over detection, and winner derivation are **infra-level
facts**, surfaced via `observations.pending_players`, `games.status`, and
`game_outcomes`. The rules unit never re-derives them.

```dart
// v1/rules.dart
import 'package:flutter/material.dart';
import 'package:eigen_engine/core/game/game_module.dart';
import 'package:my_app/game/v1/data/models/game_models.dart';
import 'package:my_app/game/v1/presentation/my_game_content.dart';

class MyGameRulesV1
    extends GameRules<ObservationData, ActionData, GameConfigData> {
  const MyGameRulesV1();

  // ── Codec: the Freezed mirror of the TS unit's `schemas`. ──
  @override
  GameConfigData parseConfig(Map<String, dynamic> json) =>
      GameConfigData.fromJson(json);

  @override
  ObservationData parseObservation(Map<String, dynamic> json) =>
      ObservationData.fromJson(json);

  @override
  ActionData parseAction(Map<String, dynamic> json) =>
      ActionData.fromJson(json);

  @override
  Map<String, dynamic> serializeAction(ActionData action) => action.toJson();

  // ── Legality: transcription of the TS applyAction's legality half. ──
  @override
  bool isValidAction({
    required ObservationData obs,
    required List<int> pending,
    required ActionData data,
    required int playerIndex,
    required GameConfigData config,
  }) {
    // Boundary / empty-cell / rule-specific legality.
    // Do NOT re-check whose turn it is for the sequential case —
    // the caller already gated on pending.contains(myPlayerIndex).
    return true;
  }

  @override
  Widget buildContent(GameContentContext context) =>
      MyGameContent(content: context);

  // Display-only twins of the TS v1 hooks — keep them in sync with
  // _lib/game/v1.ts (the server recomputes both, so drift only breaks UX).
  @override
  String? ratingPool(RatingPoolArgs args) => null;

  @override
  bool botSeatable(BotSeatableArgs args) => true;
}
```

#### `isValidAction` parameters across game styles

All parameters are passed on every call so the contract stays uniform. Your
rules unit ignores whatever it doesn't need.

| Game                                            | `obs`                   | `pending`                           | `data`          | `playerIndex`              |
| ----------------------------------------------- | ----------------------- | ----------------------------------- | --------------- | -------------------------- |
| **TicTacToe** (sequential, no ownership)        | board                   | ignored                             | target cell     | ignored                    |
| **Chess** (sequential, piece ownership)         | board                   | ignored                             | from/to squares | used — "is that my color?" |
| **Set** (any-player, race)                      | face-up cards           | used — "am I still eligible?"       | the set of 3    | ignored                    |
| **Rock-Paper-Scissors** (simultaneous)          | who has submitted       | used — "am I still pending?"        | my choice       | used — only update my slot |
| **Exploding Kittens** (sequential + interrupts) | hand, discard, deck top | used — main-turn vs. Nope interrupt | the card        | used — "do I hold this?"   |

Concrete examples:

- **Chess** — read `data.from`, look up the piece on `obs.board`, return false
  unless the piece color matches `playerIndex`.
- **Exploding Kittens** — if `data.card == Nope`, only check that
  `obs.hand[playerIndex]` contains a Nope (anyone may Nope, even if not in
  `pending`). Otherwise, require `pending.contains(playerIndex)`
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

The `GameModule` is the thin container registered with the engine — the
same-named twin of the TS `GameModule` in `_lib/game.ts`: the `versions` map
(one `GameRules` unit per `schema_version`, step 2) plus the
version-independent creation/about UI (creation always targets the latest
version).

```dart
// game_module.dart
import 'package:flutter/material.dart';
import 'package:eigen_engine/core/game/game_creation_spec.dart';
import 'package:eigen_engine/core/game/game_module.dart';
import 'package:my_app/game/v1/rules.dart';

class MyGameModule extends GameModule {
  const MyGameModule();

  // One GameRules per schema_version this build ships — same keys as the TS
  // GameModule.versions in _lib/game.ts. New games are created at the
  // highest key; a drained old version is retired by deleting its entry.
  @override
  Map<int, GameRules> get versions => const {1: MyGameRulesV1()};

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
  Widget buildRules(BuildContext context) => const MyGameRules();
}
```

`buildContent` takes a single
[`GameContentContext`](../lib/core/game/game_module.dart) and your content
widget consumes it directly (`MyGameContent(content: context)`) rather than
re-declaring and unpacking each field — so adding new infra data later never
changes the signature or forces every game to update. The context exposes the
two halves of the live game as separate members — `config` (parsed once via
your `parseConfig`, long-lived; cast it to your concrete type) and `frame`
(the per-event observation snapshot: `frame.observation`,
`frame.pendingPlayers`, `frame.version`, `frame.timing`) — plus `gameStatus`,
`outcomes`, `actionPending`, `onAction`, `onInvalidAction`, `playersContext`,
`isReplay`, and the convenience getters `mySeat` (delegates to
`playersContext.mySeat`) and `timing` (delegates to `frame.timing`).
Your rules-unit methods (`isValidAction`, `serializeAction`, helpers) are
available as `this` — pass the unit (or just what a widget needs) down to
private widgets explicitly.

`isReplay` is `true` when the frame is being stepped through in replay (a
finished game, viewed frame by frame) rather than played live. A game never
_needs_ it to stay correct — the frame is a real observation, `onAction` is
inert, and input already disables off the pending set — but it is there for
replay-only presentation, e.g. surfacing move-by-move narration or hiding
"your turn" hints. During replay `gameStatus` is `finished` for every frame,
and `outcomes` is populated only on the final frame (so a win banner appears
at the end, not mid-replay). When `mySeat` is a `Viewer` the current user did
not play in the game — a non-participant replaying a public game — which only
happens in replay. The same `buildContent`, cue embedding, and successor-frame
animation contract (see **Animating transitions**) serve live play and replay
alike; you write the rendering once.

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
a time — the harness rejects a hook envelope with more than one pending seat in
a budget-timed game as a game bug (see `engine_architecture.md §3`).

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

Receives pre-parsed, typed data. No JSON parsing here — it happens once per
network event in the session provider, through your rules unit's codec.

The rules unit passes itself (or just the members a widget needs) into the
content widget it builds — infra deliberately hands widgets no rules access,
so the dependency stays explicit:

```dart
// In MyGameRulesV1:
@override
Widget buildContent(GameContentContext context) =>
    MyGameContent(rules: this, content: context);
```

```dart
import 'package:flutter/material.dart';
import 'package:eigen_engine/core/game/game_module.dart';
import 'package:eigen_engine/core/game/game_outcome.dart';
import 'package:eigen_engine/core/game/game_status.dart';
import 'package:my_app/game/v1/data/models/game_models.dart';
import 'package:my_app/game/v1/rules.dart';
import 'package:my_app/game/v1/presentation/my_game_board.dart';

class MyGameContent extends StatelessWidget {
  const MyGameContent({super.key, required this.rules, required this.content});

  /// This version's rules unit (legality checks, action codec, helpers).
  final MyGameRulesV1 rules;

  /// The infra-provided context: parsed config, current observation frame,
  /// player identities, outcomes and action callbacks. Pull what you need off
  /// it in `build` — adding new infra data never changes this widget's
  /// constructor.
  final GameContentContext content;

  @override
  Widget build(BuildContext context) {
    // Pull the typed locals your content needs off the context. Cast the
    // config and observation to your concrete types — the cast is sound by
    // construction: this unit's parseConfig()/parseObservation() produced
    // them.
    final config = content.config as GameConfigData;
    final observation = content.frame.observation as ObservationData;
    final pendingPlayers = content.frame.pendingPlayers;
    final gameStatus = content.gameStatus;
    // Null when a Viewer (a non-participant replaying) — every "is it me"
    // check below then simply never matches, which is exactly right.
    final mySeatIndex = content.mySeat.indexOrNull;
    final outcomes = content.outcomes;
    final actionPending = content.actionPending;
    // Also available: content.timing (clocks), content.playersContext (names).

    final isMyTurn = pendingPlayers.contains(mySeatIndex);
    final isGameOver = gameStatus == GameStatus.finished;
    final didIWin = outcomes.any(
      (o) => o.playerIndex == mySeatIndex && o.result == OutcomeResult.win,
    );
    final isDraw =
        isGameOver && !outcomes.any((o) => o.result == OutcomeResult.win);
    final canPlay = gameStatus == GameStatus.active && isMyTurn && !actionPending;

    return MyGameBoard(
      board: observation.board,
      enabled: canPlay,
      onCellTap: (position) {
        final action = ActionData(position: position);
        final legal = rules.isValidAction(
          obs: observation,
          pending: pendingPlayers,
          data: action,
          // Non-null here: the board is only `enabled` on your own turn,
          // which a Viewer never has.
          playerIndex: mySeatIndex!,
          config: config,
        );
        if (legal) {
          // Infra wires onInvalidAction to HapticFeedback.selectionClick() —
          // do not import flutter/services or choose the haptic yourself.
          content.onAction(rules.serializeAction(action));
        } else {
          content.onInvalidAction();
        }
      },
    );
  }
}
```

---

## Animating Transitions

Animation is presentation of **frame transitions**. The engine gives you three
guarantees to build on; everything visual stays in your widgets.

**1. You see every frame, in order.** Observations are append-only server-side
(one row per seat per state version) and the client stream is gap-recovered:
if Realtime drops an event, the missing frames are fetched and delivered in
version order. Opponent moves, bot moves, interrupt resolutions — each arrives
as its own `GameFrame`, so "animate the change between the previous frame and
this one" is a sound strategy for **all** moves, not just your own. The one
exception is a cold (re)load: the stream starts at the *latest* frame with no
predecessor, so render it statically (see rule 3).

**2. The observation tells you what happened — don't diff frames.** Frame
diffing can't recover causality (a hidden-info move with no visible footprint,
two causes with the same footprint, a composite move-battle-capture whose
choreography the diff has collapsed). Instead, your TS `computeObservation`
receives the transition's `cause` (the move or event that produced the state)
and embeds **each seat's view of it** into that seat's slice — a `lastMove` /
`events` field in your observation payload, shaped however your animation
needs (ordered beats included). Visibility is automatically per-seat because
the embedding happens inside the projection. Replay frames carry the same
cues, so one animation pipeline serves live play and replay.

**3. Animate a cue only when you rendered its predecessor.** A cue describes a
transition. On a cold load (or a stale rejoin) you receive a frame whose
predecessor you never rendered — render the cue as static "last move" info (a
highlight, chess.com-style), not as an animation. In practice: keep the
previously rendered frame's `version` in your widget state; play the entrance
animation only when the incoming frame is its direct successor.

### Instant feedback (optional)

A turn-based round trip (submit → commit → Realtime) is typically well under a
second. Latency-hiding is **game-owned**: infra never predicts game state, it
just tells you how your submit resolved. Two layers, cheapest first:

- **Outcome-independent feedback needs no bookkeeping**: lift the piece on
  tap, slide it toward the target, play the sound — local widget state,
  resolved when the server frame lands. `GameContentContext.actionPending`
  already marks the in-flight window.
- **Optimistic rendering** pairs your unit's `previewAction` with the
  `ActionSubmitResult` future `GameContentContext.onAction` returns. Compute
  the predicted observation with `previewAction` (its body is the
  state-change half of your TS `applyAction`, transcribed) and render it
  from local widget state while the future is pending. The result tells you
  exactly what the frame stream will do next:
  - `committed` — the confirming frame is guaranteed to be the *next* frame
    you receive (the optimistic lock means no other frame can commit in
    between); clear the local prediction when it arrives and let the normal
    transition pipeline take over.
  - `rejected` — the move definitively did not commit and no frame is
    coming (infra has already shown the error); revert — the board visibly
    snaps back.
  - `unconfirmed` — the submission failed in transit and the server may
    still have committed it; revert, and if the move did commit its frame
    arrives over Realtime and re-applies it.

  `previewAction` returning null means "don't predict this move" — required
  for moves whose outcome depends on hidden information (a combat
  resolution, a reveal, a deck draw); those are simply server-driven.
  Predictions are for the actor's own moves only; opponents' moves always
  arrive as server frames (rule 1).

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

// Get the current user (null when a Viewer — a non-participant replaying)
final me = playersContext.me;
me?.info.username;         // your username
me?.playerIndex;           // your seat index

// Or branch on the seat explicitly
switch (playersContext.mySeat) {
  case Seated(:final index): // you play seat `index`
  case Viewer():             // you're a non-participant watching a replay
}

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
> and `computeObservation` hook can shape them freely. Infra only tracks the
> seat index (`playerIndex`) and `type`.

### `PlayersContext` API

| Member             | Type                   | Description                            |
| ------------------ | ---------------------- | -------------------------------------- |
| `players`          | `Map<int, GamePlayer>` | All players keyed by index             |
| `mySeat`           | `MySeat`               | Sealed `Seated(index)` \| `Viewer` — the user's seat, or a non-participant replay viewer |
| `operator [](int)` | `GamePlayer`           | Non-nullable access by index           |
| `me`               | `GamePlayer?`          | Current user's player; null for a `Viewer` |

`MySeat` is a sealed type: `Seated(int index)` for a participant, `Viewer()`
for a non-participant replaying a public game (only in replay). `switch` on it,
or read `mySeat.indexOrNull` (the index, or null for a viewer) for "is it my
turn" style checks where a viewer simply never matches.

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

1. **Implement `LocalBot`** in your game package (in the version folder, alongside its `GameRules`,
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
       required GameRules<MyObservation, MyAction, MyConfig> rules,
       required MyConfig gameConfig,
       required int seatIndex,
       required Map<String, dynamic> botConfig, // bots.config, may be empty
     }) => null; // stateless bot — a stateful one returns its initial brain

     @override
     ({MyAction action, Null state}) chooseAction({
       required GameRules<MyObservation, MyAction, MyConfig> rules,
       required MyConfig gameConfig,
       required MyObservation observation,   // already typed — no cast
       required int seatIndex,
       required Null state,
     }) {
       // ...pick a legal move (use `rules.isValidAction` for legality)...
       return (action: MyAction(cell: bestCell), state: null);
     }
   }
   ```

   A **stateful** bot (an MCTS tree, a Stratego/poker belief model) sets
   `TState` to its brain type: `createState` seeds it, and each `chooseAction`
   returns the **next** state — re-rooted to the played move, beliefs folded in
   — which the driver commits **only when the action is accepted**.

   `LocalBot` is generic over the same `<observation, action, config>` triple
   as your `GameRules` (plus `TState`), so you write it like the rules unit
   and get a fully typed `observation` in and a typed action out — **no
   casts, no hand-rolled JSON**. The driver serialises your action via
   `rules.serializeAction`, the same seam the human path uses, so the two can
   never drift.

   **The engine runs `chooseAction` off-thread** (`Isolate.run`), so heavy
   search never blocks a UI frame — no `compute()` of your own. In return it
   must be **pure** (never mutate `state` or touch the outside world; seed any
   randomness from `state` and return the advanced seed), and everything it
   touches — bot, rules unit, configs, observation, action, `state` — must be
   **isolate-sendable** (plain data, no clients/ports). A bot needing **large
   static data** (a pretrained net) belongs **server-side**: it would be
   re-copied into the isolate every move.

   **What `chooseAction` returns is an action plus the next state** — the action
   is the same shape a human move produces (see _Designing action data_ below);
   you design it, and the server validates it in `applyAction`.

2. **Register instances** on the version's `GameRules` — this presence _is_
   the local-bot support flag (empty default ⇒ no bot UI). Bots are
   per-version because a `LocalBot` is generic over that version's payload
   types; a `v2` unit re-lists (or re-adapts) the bots it supports:

   ```dart
   // in v1/rules.dart
   @override
   List<LocalBot> get localBots => const [
     MinimaxBot(username: 'easy_ai', depth: 2),
     MinimaxBot(username: 'hard_ai', depth: 6),
   ];
   ```

   One class can back several personas via constructor args **or** the DB
   `bots.config` handed to `createState` (N:1). The engine's driver resolves
   the game's version unit and matches a pending bot seat to the `localBots`
   entry whose `username` equals the seat's `bots.username`, runs
   `chooseAction`, and submits — you write no wake/submit plumbing. (The driver spots the bot's turn from the **host's** observation
   row, so a `computeObservation` that narrows `pending_players` must keep
   pending bot seats visible to the host — see Hook 3.)

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
- **Ack the wake with a 2xx *before* computing.** The wake response means
  "queued", never "acted" — the engine gives you ~10 seconds to ack, then
  treats the wake as undelivered and **retries it a few times** with short
  backoff. Two contractual consequences: don't compute the move in the
  request handler (a slow think would read as a failed delivery), and
  tolerate **duplicate wakes for the same `version`** (recompute or ignore —
  a duplicate submitted action is safely rejected by the version check).
- The bot computes a move and `POST`s it to the **`bot/action`** edge-function
  route as `{ payload, signature }`, where `payload` is the signed JSON string
  `{ game_id, bot_id, player_index, version, data }`.

**Authentication** (handled for you; you provision one derived key):

Both directions use the **same per-bot HMAC key**, derived from the platform's
single master secret as `HMAC-SHA256(BOT_SIGNING_SECRET, bot_id)` — no per-bot
secret is stored anywhere. The bot is given this derived key once. A signature
is always `"v1," + base64(HMAC-SHA256(key, "<domain>:<message>"))` — the signed
bytes are prefixed with a direction tag so a captured signature can never be
replayed into the other direction, and the `v1,` scheme prefix leaves room to
evolve the format:

- **Wake (us → bot):** the engine sends `x-wake-signature` = the signature over
  `"wake:" +` the exact request body; your bot recomputes it over the raw body
  and rejects on mismatch.
- **Action (bot → us):** your bot sends `signature` = the signature over
  `"action:" +` the exact `payload` it posts; the `bot/action` route recomputes
  the key and verifies it. This is the real security boundary — the wake never
  authorizes a move (the server re-validates every action under lock), so a
  forged wake can at most waste the bot's compute.

So the bot deployment holds **one derived key** (it signs actions and verifies
wakes). Server-bot games must be **timed** (the turn deadline is the liveness
backstop for a bot that stays down past the wake retries).

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
const sign = (domain, s) =>
  "v1," +
  createHmac("sha256", SECRET)
    .update(`${domain}:`).update(s).digest("base64");

createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", async () => {
    const raw = Buffer.concat(chunks); // the RAW bytes
    const a = Buffer.from(sign("wake", raw));
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
      body: JSON.stringify({ payload, signature: sign("action", payload) }),
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
SIG="v1,$(printf 'action:%s' "$PAYLOAD" \
  | openssl dgst -sha256 -hmac "$BOT_KEY" -binary | base64)"
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
`botSeatable`. `config` is **public read-only reference data** — `app_bots`
exposes it for both local and server bots (the pickers and the seatable filter
read it), so never put secrets there.

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
   tap and submits it through the rules-unit seam:
   `content.onAction(rules.serializeAction(action))`.
2. **Producer (local bot)** — `LocalBot.chooseAction` returns that **same typed
   `ActionData`**; the infra driver serialises it through the very same
   `rules.serializeAction`. A human tap and a bot decision are interchangeable.
3. **Consumer (server)** — your `applyAction` hook receives the resulting JSON
   as `p_data` (jsonb) and is the **only authority**: it validates legality and
   applies it. Never trust the client to have sent a legal move — a local bot's
   move has exactly the same untrusted provenance as a human's.

The action payload is a plain JSON object whose keys are yours to choose; keep
it minimal — it is **only** "what the move is". Infra supplies the seat
(`p_player_index`), version, RNG seed, config, and schema version to
`applyAction` as **separate parameters**, so never put them in the payload. It
is passed straight through as the hook's `p_data` with no infra envelope; for
the placeholder TicTacToe game that is literally `{"position": 0–8}`
(`(p_data->>'position')::INT`).

The engine gives you a **fully typed action seam**, the output mirror of
`parseObservation`: `GameRules` is generic over `TAction`, your game defines a
Freezed `ActionData` (`fromJson`/`toJson`) alongside `ObservationData`, and
the unit's `serializeAction` is the **single** place a typed action becomes
JSON (`parseAction` is its inverse, used by infra to re-type an in-flight or
logged action). Both Dart producers stay typed end to end and route through
it, so they cannot drift:

```dart
// the one action model
@freezed
abstract class ActionData with _$ActionData {
  const factory ActionData({required int position}) = _ActionData;
  factory ActionData.fromJson(Map<String, dynamic> json) =>
      _$ActionDataFromJson(json);
}

// rules unit — the only typed action → JSON step
@override
Map<String, dynamic> serializeAction(ActionData action) => action.toJson();

// human (content widget):  content.onAction(rules.serializeAction(action));
// local bot (chooseAction): return ActionData(position: best);  // driver serialises
// server bot (any language): emits the same JSON shape, e.g. {"position": best}
```

The seam stays typed inside Dart, but the **wire boundary** (what crosses to
`p_data`) is `Map<String, dynamic>` — that is exactly what reaches the hook. A
**server bot runs in another language, so it cannot share the Dart type**; its
uniformity is guaranteed at the JSON-shape level only. That makes `applyAction`
(the single consumer) plus the version unit's `action` Zod schema the
**one source of truth** that the Dart `ActionData` model and the server bot both
mirror — the edge function rejects (400) any action `data` that fails the game's
version `action` schema before your hook runs. Version the shape by shipping a
new `GameRules` unit when it changes (see **Shipping a new schema version**).
See Hook 2 (`applyAction`) for the consumer contract.

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

A game's server-side rules surface is a **`GameModule`: one TypeScript
`GameRules` unit per `schema_version`**, each bundling the Zod payload schemas
plus six hooks — `initialState`, `applyAction`, `computeObservation`, plus
optional `ratingPool`, `applyLifecycle`, and `botSeatable`. They all live in the
**`game` edge function**: the units in `functions/_lib/game/v1.ts` (`v2.ts`,
…) and the registry you export from `functions/_lib/game.ts` — see **The game
edge function** below. There is **no SQL to write for the rules**; the gated
`engine_*` RPCs the edge function commits through are infra and stay
untouched.

The engine's **backend** is **vendored** into your app — run
`dart run eigen_engine:sync_supabase` from the app directory. It copies the
engine's `migrations/*.sql`, the single `engine` edge function (its harness +
the shared `_engine` framework, serving the `game`, `social`, `internal`, and
`bot` route groups), and `seed.sql` into your `supabase/`, leaving your
app-owned files (any game migration, your `functions/_lib/game.ts`) untouched.
Ratings (OpenSkill) and push notifications run inside the edge function now —
there are no separate `update-ratings` / `refresh-fcm-token` functions. Commit
everything, then `supabase db reset`. Re-run when you bump the engine version.
See **Supabase project setup** below for the one-time config.

You normally write **no game SQL at all**. (A migration is only needed if your
game adds its own tables; the rules themselves are pure TypeScript.)

### The game edge function

The rules run as TypeScript inside the engine-owned edge functions (the whole
`_engine/` framework — Hono routing, auth, gated reads/commits — is bundled in
on import). There are **four** functions — `game` (client JWT), `social` (client
JWT), `internal` (cron/webhook secret), `bot` (per-bot HMAC) — but you implement
only the `GameModule`; the framework wires it into all of them. Ownership
mirrors the backend's vendoring rule:

| Path                                                           | Owner   | On `sync_supabase`                      |
| -------------------------------------------------------------- | ------- | --------------------------------------- |
| `functions/_engine/**`, `functions/_types/**`                  | engine  | re-vendored (overwritten + pruned)      |
| `functions/{game,social,internal,bot}/*` (`index.ts`, config…) | engine  | re-vendored (overwritten + pruned)      |
| `functions/_lib/**` (`game.ts`, `game/v1.ts`, fixtures…)       | **you** | scaffolded **once**, then never touched |
| `functions/_tests/**` (your twin-fixture / EF test entrypoints) | **you** | never touched (not in the vendored set) |

(`deno.lock` is git-ignored and regenerated per project, so it is never copied
or pruned — your local lockfile is left alone.)

So your entire server-side rules surface is one `GameRules` class per version
(each with its **Zod schemas per payload** as the single source of truth —
derive the payload types with `z.infer` and the whole unit is typed
end-to-end) plus the two-line registry in `game.ts`:

```ts
// _lib/game/v1.ts
import { z } from "zod";
import {
  IllegalMoveError,
  passthroughObservation,
} from "engine/game-engine.ts";
import type {
  ApplyActionArgs,
  BotSeatableArgs,
  Envelope,
  ApplyLifecycleArgs,
  GameRules,
  InitialStateArgs,
  RatingPoolArgs,
} from "types/engine.types.ts";

const stateSchema = z.object({ board: z.array(z.number()).length(9) });
const actionSchema = z.object({ position: z.number().int().min(0).max(8) });
const configSchema = z.object({});

type State = z.infer<typeof stateSchema>; // `type`, not `interface`
type Action = z.infer<typeof actionSchema>;
type Config = z.infer<typeof configSchema>;

class MyGameV1 implements GameRules<State, Action, Config> {
  readonly schemas = {
    state: stateSchema,
    action: actionSchema,
    config: configSchema,
  };
  initialState(args: InitialStateArgs<Config>): Envelope<State> {/* … */}
  applyAction(
    args: ApplyActionArgs<State, Action, Config>,
  ): Envelope<State> {
    /* args.state / args.data are already parsed + typed — no casts.
       throw new IllegalMoveError("…") to reject; return the new envelope */
  }
  applyLifecycle(args: ApplyLifecycleArgs<State, Config>): Envelope<State> {
    /* forfeit/timeout consequence */
  }
  computeObservation = passthroughObservation<State, Action, Config>; // perfect-info
  ratingPool(args: RatingPoolArgs<Config>): string | null {
    return null; // unrated; return a pool name (e.g. "rapid") to rate
  }
  botSeatable(args: BotSeatableArgs<Config>): boolean {
    return true; // every bot seatable; tighten per your config
  }
}

export const rulesV1: GameRules = new MyGameV1();
```

```ts
// _lib/game.ts
import type { GameModule } from "types/engine.types.ts";
import { rulesV1 } from "./game/v1.ts";

export const gameModule: GameModule = { versions: { 1: rulesV1 } };
```

The `GameRules`/`GameModule` contracts (the `Args` types, `Envelope`) are
defined in `functions/_types/engine.types.ts` — read it for the authoritative
signatures; `IllegalMoveError`, `passthroughObservation` (the perfect-info
default) and the version-boundary helpers live in
`functions/_engine/game-engine.ts`.

**The harness enforces the version boundary for you.** Each route first
validates the request body's _envelope_ (ids, versions, timing fields) against
an engine-owned Zod schema — a malformed request 400s before any handler code
runs. Then the framework resolves the game row's `schema_version` entry from
`versions` and parses every payload through **that unit's** schemas before
invoking its hooks, so hook bodies never see unvalidated JSON — and never
another version's shape:

| Payload                                      | On failure                          |
| -------------------------------------------- | ----------------------------------- |
| client `config` at create                    | 400 (Zod issues in the message)     |
| client/bot action `data`                     | 400                                 |
| `schema_version` not in `versions` at create | 400                                 |
| stored `state`/`config` on read              | 500 (corruption / missed version)   |
| loaded game's version not in `versions`      | 500 (EF deployed behind its data)   |
| hook-returned `state`                        | 500 (validated before every commit) |

Client payloads flow onward **sanitized** — unknown keys stripped, defaults
applied — into your hooks, the `actions` log, and `games.config`. Two rules keep
this sound: keep schemas **transform-free** (what parses is what persists, and
hook output is re-validated against the same `state` schema), and derive payload
types as `type` aliases (an `interface` fails the engine's `JsonObject`
constraint).

### Shipping a new schema version

A breaking rules or payload-shape change never edits an existing version unit —
it ships as a new one. Games created earlier keep running against their own
unit until they drain; nothing anywhere branches on version.

1. **TS:** copy `_lib/game/v1.ts` → `_lib/game/v2.ts` (import whatever didn't
   change from `./v1.ts` instead of duplicating it), make the change, and
   register it in `_lib/game.ts`:
   `versions: { 1: rulesV1, 2: rulesV2 }`.
2. **Dart:** create `lib/game/v2/` the same way (a `v2/rules.dart` may reuse
   v1 widgets/models by import) and register it in the module:
   `versions: {1: MyGameRulesV1(), 2: MyGameRulesV2()}`.
3. **Deploy order:** edge function first, then the app release. The server
   accepting `2` while older clients still create at `1` is fine — creation is
   validated against the *requested* version, and each game is served by its
   own unit.
4. **Retiring a version:** once no games at an old version remain active (and
   you no longer need their replays), delete its map entry and folder on both
   sides. Version keys are **sparse** — `supportsSchema` / creation check map
   membership, not `<= latest`.

Local bots re-list per version (`GameRules.localBots`), and the `bots` table's
`schema_version` column declares the highest version each server bot supports —
bump it when the bot learns the new shapes.

`applyAction` rejects a rule-breaking move by throwing `IllegalMoveError` (→
HTTP 400 with the message); any other throw is treated as a game bug (→ 500).
The infra has already confirmed it is the acting seat's turn at the expected
version before calling, so do not re-check turn order. `ratingPool` and
`botSeatable` need **Dart twins** on the same version's Dart `GameRules` (the client gates the
create-dialog Rated/Casual toggle and the bot pickers locally); the server stays
authoritative. Randomness comes from `args.rng` — a deterministic
per-transition generator (`rand-seed`) the harness derives for you; draw as
many values as you need (`rng.next()` → float in `[0, 1)`) and never cache it
across hook calls.

Iterate locally with `supabase functions serve` (or
`deno check
--config supabase/functions/engine/deno.json supabase/functions/engine/index.ts`
for a quick type-check). Because `game-engine.ts` has no Supabase/Deno runtime
dependency, your gameModule is unit-testable in isolation. Deploy with
`supabase functions deploy engine`.

Once your app is in production, migrations become append-only and schema changes
must stay backward-compatible with app versions still in the wild — see
[README → Versioning & backward
compatibility](../README.md#versioning--backward-compatibility)
(expand/contract, mobile update lag, in-flight game state).

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
   - `[edge_runtime]` + the **`[functions.engine]`** block (`verify_jwt = false`
     — auth is per route group _inside_ the function: user JWT for
     `game`/`social`, secret API key for `internal`, per-bot HMAC for `bot`),
     with `import_map` / `entrypoint` pointing at `./functions/engine/` — copy
     it verbatim from the engine config. The block is what makes the function
     deployable; without it `supabase functions deploy`/`serve` won't pick it
     up.
2. **Vendor the backend:** `dart run eigen_engine:sync_supabase` (migrations +
   functions + seed), then commit. The first run scaffolds
   `functions/_lib/game.ts` and prints a reminder to add the
   `[functions.engine]` config block; implement your `gameModule` in that file
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
from the **Dart twin** of this method (plus its guest status) and sends a
concrete `rated`. The edge function recomputes
`canBeRated = pool != null && !guest` and **rejects a mismatch** (422) rather
than coercing. There is no _forced-rated_ mode — an ineligible config or a guest
must send `rated = false`, and the create dialog hides/forces the toggle
accordingly. Pool names stay server-authoritative.

**Default**: `null` (all games unrated until overridden).

```ts
ratingPool(args: RatingPoolArgs<Config>): string | null {
  if (args.access !== "public") return null;     // only public games rate
  if (args.turnSeconds != null) return "rapid";  // map timing mode → pool
  if (args.budgetSeconds != null) return "daily";
  return null;                                    // untimed public ⇒ unrated
}
```

Keep a **Dart twin** on the same version's Dart `GameRules` with the identical rule so the New
Game dialog can show the live Rated/Casual badge and gate the toggle (hidden
when the pool is `null` or the user is a guest). The twin and this method must
agree — the server rejects the create if they don't.

---

### Hook 0b: `botSeatable(args: BotSeatableArgs<Config>): boolean`

Optional. Decides whether a bot may be seated into a game with the chosen
config. Called by the edge function before seating (the `add-bot` and
`create-solo` routes); return `true` to allow. `args` carries `botConfig` (the
bot's declared capabilities, from `bots.config` — opaque JSON, unversioned by
your game schemas) and `gameConfig` (`games.config`, already parsed against the
game's version config schema, so it arrives as your typed `Config`). It is the
**single source of truth** for config compatibility, and gates the variant axis
`schema_version` can't (a bot can match the schema but not the rules variant).

**Default**: `true` (every bot seatable). Override to gate by the capability
keys your game stores in `bots.config` — the engine imposes no schema on
`bots.config`.

```ts
botSeatable(args: BotSeatableArgs<Config>): boolean {
  // Example: a chess bot lists supported variants in its config; default "standard".
  const variant = args.gameConfig.variant ?? "standard"; // typed Config
  const supported = (args.botConfig.variants as string[]) ?? ["standard"];
  return supported.includes(variant);
}
```

Keep a **Dart twin** on the same version's Dart `GameRules` so the bot pickers filter the cached
`app_bots` catalog by the same verdict — no client-side divergence, and the
client never offers an opponent that seating would reject.

---

### Hook 1: `initialState(args: InitialStateArgs<Config>): Envelope<State>`

`args`: `rng`, `playerCount`, plus the `HookContext` (`config` — parsed and
typed). There is no version field in any hook's args — your unit *is* the
version. Returns the starting envelope — must include `state` and
`pending_players`; may include `turn_seconds`. The returned `state` is
validated against the unit's `state` schema before it is committed.

```ts
initialState(args: InitialStateArgs<Config>): Envelope<State> {
  // Draw setup randomness (shuffle, deal, first player…) from args.rng —
  // deterministic per transition, so a replay re-derives the same draws.
  const first = Math.floor(args.rng.next() * args.playerCount);
  return {
    state: { board: [], action_count: 0 },
    pending_players: [first],
    // turn_seconds: 60, // optional: override timing for the very first action only
  };
}
```

**Return envelope fields:**

| Field             | Required | Description                                                                                                                            |
| ----------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `state`           | yes      | Pure game payload. No whose-turn or winner info.                                                                                       |
| `pending_players` | yes      | 0-based indices that may act first.                                                                                                    |
| `turn_seconds`    | no       | Fixed deadline for the first action only (overrides game-level timing for this action). Omit to use the game's configured timing mode. |

---

### Hook 2: `applyAction(args: ApplyActionArgs<State, Action, Config>): Envelope<State>`

`args`: `state`, `pending`, `data` (the move), `playerIndex`, `rng`, plus the
`HookContext`. `state`, `data`, and `config` arrive parsed against this unit's
schemas — a move whose `data` fails the `action` schema is rejected with
400 before this hook runs, so validate **game-rule** legality only, not shape.
The infra has **already** confirmed it is this seat's turn at the expected
version under the lock, so do not re-check turn order either. Reject a
rule-breaking move by throwing `IllegalMoveError` (→ 400 with the message); any
other throw is a game bug (→ 500).

```ts
applyAction(
  args: ApplyActionArgs<State, Action, Config>,
): Envelope<State> {
  // 1. Validate the move is legal; reject if not.
  if (!isLegal(args.state, args.data, args.playerIndex)) {
    throw new IllegalMoveError("cell already occupied");
  }
  // 2. Apply it to produce the new state, drawing any randomness (card draw,
  //    dice…) from args.rng — as many values as needed.
  // 3. Decide who acts next (empty ⇒ game over) and whether there is an outcome.
  const newState = /* … */ args.state;
  const ongoing = /* … */ true;
  return {
    state: newState,
    pending_players: ongoing ? [(args.playerIndex + 1) % 2] : [],
    ...(ongoing ? {} : { outcome: /* OutcomeEntry[] */ [] }),
  };
}
```

**Return envelope fields**:

| Field             | Required | Description                                                                                                                                                                                                |
| ----------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `state`           | yes      | Updated game payload.                                                                                                                                                                                      |
| `pending_players` | yes      | Who acts next. Empty array = game over.                                                                                                                                                                    |
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
- In `computeObservation`, put `{"is_eliminated": true, "placement": 4}` in the
  eliminated player's observation slice — the content widget uses this to show
  "You were eliminated" immediately.
- When the game ends, build the full `outcome` array including eliminated
  players with their correct `"placement"` values for ELO.

---

### Hook 2b: `applyLifecycle(args: ApplyLifecycleArgs<State, Config>): Envelope<State>`

`args`: `state`, `pending`, `type`, `data` (a typed `LifecycleAction` union — no casts
needed), `rng`, plus the `HookContext`. Decides the consequence of a
**lifecycle action** — the engine-owned species of action (see `actions.kind`),
operating on the game from outside its rules. It may be player-triggered (a
resign) or engine-triggered (timeout, purge). Unlike `applyAction` it **cannot
be illegal** — it always resolves to an envelope. `type` always equals
`data.type`:

| `type`           | Trigger                                             | Which seat(s)                                                           |
| ---------------- | --------------------------------------------------- | ----------------------------------------------------------------------- |
| `'timeout'`      | the `expire` route (client nudge) or the cron sweep | **all of `args.pending`** ran out of time — no `player_index` in `data` |
| `'forfeit'`      | the `forfeit` route — a voluntary resign            | `args.data.player_index` — the single target seat                       |
| `'auto_forfeit'` | the account-deletion purge (engine-driven)          | `args.data.player_index` — the single target seat                       |

A `timeout` shares one deadline across all pending seats, so resolve the **whole
set at once** — you may declare a draw when everyone flags. A forfeit targets
one seat; the two forfeit kinds share a shape, and most games resolve them
identically (as the example below does) — the split exists so a game *may*
choose different consequences for a purged account (e.g. a draw rather than a
loss). All three return the same envelope as `applyAction` (`state`,
`pending_players`, optional `outcome`, optional `turn_seconds`).

```ts
applyLifecycle(args: ApplyLifecycleArgs<State, Config>): Envelope<State> {
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
  };
}
```

A multiplayer forfeit (or a timeout that leaves the game live) might just
advance past the affected seats instead of ending the game:

```ts
// Skip: drop the timed-out seats from pending, game continues (some N-player games).
return {
  state: args.state,
  pending_players: [], // hook recomputes the next pending set
};
```

Two contracts the harness enforces on the envelope (game bug → 500, before
commit — same as the state-schema and budget-pending checks):

- A forfeit **must remove its target seat from `pending_players`** — a
  forfeited seat left pending becomes a ghost after the account purge, holding
  a deadline the timeout sweep fires at forever.
- **No pending seat may lack an identity.** After a purge, a departed seat has
  neither `user_id` nor `bot_id` and can never act; derive pending from who is
  still *in* the game, not from the participant count.

---

### Hook 3: `computeObservation(args: ComputeObservationArgs<State, Action, Config>): ObservationSlice`

`args`: `state`, `pending`, `playerIndex`, `participantCount`, `cause`,
`isReplay`, plus the `HookContext`. The edge function fans this out once per
participant after every transition (and per historical version for replay).
Returns `{ data, pending_players }` — the slice `data` is deliberately
schema-less (`JsonObject`): it is an output-only projection the Dart client
parses. **Perfect-info games do not override this** — assign the
`passthroughObservation` default (the identity projection).

`args.cause` is **what produced this state**: `{ kind: "game", data,
playerIndex }` for a move, `{ kind: "lifecycle", data }` for a forfeit/timeout,
`null` for the initial frame. Embed whatever each seat may see of it into the
slice (e.g. a `lastMove` field) so the client can animate the transition —
see **Animating transitions** in the client half of this guide. Per-seat
visibility is automatic: the embedding happens here, in the projection.

Override for hidden-info games to strip opponent cards/hands and optionally
narrow `pending_players` — each seat's row carries its own **view** of the true
`game_states` pending set, so a reaction window (e.g. a Nope) need not reveal
who else holds an interrupt. Use `isReplay` to reveal information post-game
(e.g. all hole cards in a Poker replay).

`args.playerIndex` is `null` when the projection is for a **non-participant
replay viewer** — someone replaying a public finished game they did not play in.
This only ever happens with `isReplay = true`, so treat it like any other replay
seat and return the full revealed view; never index `state` by a `null` seat.

Narrowing is presentation only: infra keys everything authoritative — the
not-your-turn gate, timeout resolution, clock math, notifications — off the
true set, so a projection can mislead a client but never the server. Two rules
keep the clients honest:

- **Never narrow a seat's own membership out of its own slice.** If
  `args.pending` contains `args.playerIndex`, the returned `pending_players`
  must too. A seat whose own view denies it is pending never prompts its human
  (and the local-bot driver skips its compute) — the seat silently runs out
  the clock. What a slice says about **other** seats is yours to narrow.
- **Keep pending local-bot seats visible in their host's slice.** The
  local-bot driver detects a bot's turn from the host's own observation row,
  so a solo game must not hide its bot seats' pending status from the human.

```ts
// Perfect-info: assign the helper, instantiated with your payload types.
computeObservation = passthroughObservation<State, Action, Config>;

// Hidden-info: override.
computeObservation(
  args: ComputeObservationArgs<State, Action, Config>,
): ObservationSlice {
  if (args.isReplay) {
    // Finished game: reveal everything for review. Also the only path where
    // args.playerIndex may be null (a non-participant replay viewer), so don't
    // index state by it.
    return { data: args.state, pending_players: args.pending };
  }
  // Live: strip every seat's private info except this seat's. `playerIndex` is
  // only ever null in the replay branch above (a viewer), so live play always
  // has a real seat.
  const seat = args.playerIndex!;
  return {
    data: {
      ...stripOpponentHands(args.state, seat),
      lastMove: cueFor(args.cause, seat),
    },
    pending_players: args.pending,
  };
}
```

`isReplay` is `true` **only** when projecting a finished game for replay, so the
live fan-out always passes `false` (and a real seat). A non-participant's replay
of a public game additionally passes `playerIndex = null` (see above).

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

**When time expires**, infra calls `applyLifecycle` with `type = 'timeout'`. The
client-side `game/expire` route nudges the server immediately when a client
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

| Route                                                       | Purpose                                                                                                                                                                        |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `game/create` · `game/create-solo`                          | Create a game / a sole-human "vs AI" game. The EF validates timing + players, gates guests, derives the pool (`ratingPool`), and **validates the client's `rated` assertion**. |
| `game/start`                                                | `initialState` → writes `game_states` v0 + observations, inits banks, marks `active`.                                                                                          |
| `game/action`                                               | The move: runs `applyAction`, commits under the row lock (version + deadline + pending checks), fans out observations, writes outcome/ratings on finish.                       |
| `game/forfeit` · `game/expire`                              | `applyLifecycle('forfeit')` / `('timeout')`. `expire` is the client deadline nudge (cron is the backstop).                                                                        |
| `game/add-bot` · `game/local-bot-action`                    | Seat a server bot (host) / drive a local bot seat.                                                                                                                             |
| `game/replay`                                               | The caller's observation slice at every version (finished games), projected through `computeObservation` (`isReplay = true`). Participants replay their own seat; non-participants may replay a **public** game as a viewer (`playerIndex = null`). |
| `game/delete-account`                                       | Account teardown (forfeits active games, then purges).                                                                                                                         |
| `social/friend-request` · `social/accept` · `social/remove` | Friend writes; the EF gates the caller and pushes the notification.                                                                                                            |

**Client-direct RPCs** (the client calls these straight over PostgREST under
RLS): `app_join_game` / `app_join_game_by_code`, `app_cancel_game`,
`app_leave_game`, `app_lobby_games`, `app_friends_games`, `app_search_users`,
`app_local_bot_observation`, `app_bots`, `app_players`, `app_update_username`.

---

## Testing Your Game

### Twin-drift fixtures

The TS unit and its Dart twin are two hand-written halves of one contract, so
they *will* drift unless something fails when they do. The engine ships a
fixture pipeline for exactly this: **one set of JSON fixtures per schema
version, run against both sides**. The TS runner
(`_engine/twin-fixtures.ts`, vendored by the sync) executes each case through
the unit's Zod schemas, `applyAction`, and `computeObservation`; the Dart
runner (`package:eigen_engine/testing/twin_fixtures.dart`) executes the same
file through the twin's codec, `isValidAction`, and `previewAction`. A
divergence fails a test instead of degrading UX in production.

Fixtures live **beside the version units**, inside app-owned `_lib/`:

```
supabase/functions/_lib/game/
├── v1.ts
└── fixtures/
    └── v1/            # a v2 unit gets fixtures/v2/
        ├── actions.json
        └── predicates.json
```

One file holds one `schemaVersion` and a list of named cases. Three case
kinds exist (full format reference in the header of
`_engine/twin-fixtures.ts`):

```jsonc
{
  "schemaVersion": 1,
  "cases": [
    {
      "kind": "action",
      "name": "seat 0 marks an empty cell",
      "config": {},
      "state": { "board": [0,0,0,0,0,0,0,0,0], "action_count": 0 },
      "pending": [0],
      "playerIndex": 0,
      "participantCount": 2,
      "action": { "position": 4 },
      "expected": {
        "valid": true,
        "state": { "board": [0,0,0,0,1,0,0,0,0], "action_count": 1 },
        "pending": [1],
        "observation": { "board": [0,0,0,0,1,0,0,0,0], "action_count": 1 }
      }
    },
    { "kind": "ratingPool", "name": "…", "access": "public",
      "minPlayers": 2, "maxPlayers": 2, "config": {}, "expected": null },
    { "kind": "botSeatable", "name": "…",
      "gameConfig": {}, "botConfig": {}, "expected": true }
  ]
}
```

What each side checks per `action` case:

| Field                  | TS side                                                            | Dart side                                                             |
| ---------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------- |
| `config`/`state`/`action` | must parse through the Zod schemas; the parsed action must equal the fixture action (a schema that strips fields is drift) | must parse through the codec; `serializeAction(parseAction(action))` must round-trip |
| `expected.valid`       | `false` ⇒ `applyAction` throws `IllegalMoveError`; `true` ⇒ it must not | must equal `isValidAction`                                             |
| `expected.state` / `pending` / `outcome` | compared against the returned envelope (TS-only)  | —                                                                      |
| `expected.observation` | `computeObservation` of the new state for the acting seat          | `previewAction` result, when non-null (null = "server-driven", always correct) |

`expected.observation` is the shared behavioral anchor — both sides are
compared through one recorded value. For hidden-info games, add an `obs`
field (the acting seat's observation) next to `state`; perfect-info games
omit it and `state` serves both sides. A stochastic `applyAction` gets a
fixed `rngSeed` per case.

Two entrypoints wire the fixtures into your test suites — both are app-owned
(`_tests/`, like `_lib/`, is never touched by a re-sync):

`supabase/functions/_tests/twin_fixtures_test.ts`:

```ts
import { twinFixtureTests } from "engine/twin-fixtures.ts";
import { gameModule } from "lib/game.ts";

twinFixtureTests(
  gameModule,
  new URL("../_lib/game/fixtures/", import.meta.url),
);
```

`test/game/twin_fixtures_test.dart`:

```dart
void main() {
  const module = MyGameModule();
  for (final suite
      in loadTwinFixtureSuites('supabase/functions/_lib/game/fixtures')) {
    final rules = module.versions[suite.schemaVersion];
    group('twin fixtures v${suite.schemaVersion}', () {
      for (final fixtureCase in suite.cases) {
        test(fixtureCase.name, () {
          expect(rules, isNotNull);
          expect(runTwinFixtureCase(rules!, fixtureCase.json), isEmpty);
        });
      }
    });
  }
}
```

Run them (and put both in CI — the Dart half rides `flutter test`):

```sh
deno test --config supabase/functions/deno.json \
  --allow-read supabase/functions/_tests/
flutter test
```

Gotchas the fixtures are strict about:

- **Fixture payloads use the wire shape, not Dart field names.** With
  json_serializable's `field_rename: snake` (this template's `build.yaml`),
  the key is `action_count`, never `actionCount`. The TS Zod schemas must use
  the same keys — the fixture is what pins this.
- **The Dart observation type needs value equality** for the
  `expected.observation` comparison — Freezed models have it; a hand-written
  type must override `==`/`hashCode`.
- **Grow the suite with the rules.** Cover at least: one legal move (with its
  expected observation), one illegal move, one game-ending move (with
  `outcome`), and one case per `ratingPool`/`botSeatable` branch.

### Unit tests

For logic beyond the twin contract (win detection helpers, bot heuristics),
plain unit tests against the rules unit:

```dart
test('valid action is accepted', () {
  const rules = MyGameRulesV1();
  final obs = ObservationData(board: List.filled(9, 0), actionCount: 0);
  expect(
    rules.isValidAction(
      obs: obs,
      pending: [0],
      data: ActionData(position: 4),
      playerIndex: 0,
      config: const GameConfigData(),
    ),
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
6. Test forfeit: click forfeit in the game screen, confirm `applyLifecycle` runs
   with a `{ type: 'forfeit' }` action, and confirm `game_outcomes` reflect the
   expected result.
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
    `games.rated = true`, `games.rating_pool = 'rapid'`. Create an untimed
    public game → `games.rated = false`, `games.rating_pool = null`. Send
    `rated: true` for an ineligible game (null pool, or as a guest) → the
    `game/create` route rejects it **422 mismatch** (the EF validates, it never
    silently coerces).
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
  final legal = rules.isValidAction(
    obs: observation,
    pending: pendingPlayers,
    data: action,
    playerIndex: myPlayerIndex,
    config: config,
  );
  if (legal) {
    onAction(rules.serializeAction(action));
  } else {
    onInvalidAction(); // do not call HapticFeedback directly
  }
},
```

Pass it through from `GameRules.buildContent()` to your content widget as a
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
- [ ] `secret_api_key` created in Supabase Vault for production project, holding
      the project's **secret API key** (`sb_secret_…`) — the cron sweeps send it
      as the `apikey` header to `/engine/internal/*`, where `@supabase/server`'s
      `auth: 'secret'` mode validates it (no bespoke webhook secret exists)
- [ ] function secrets set via `supabase secrets set` (see
      `engine_architecture.md §21`): `BOT_SIGNING_SECRET` (server-bot HMAC key
      derivation), and `FIREBASE_CLIENT_EMAIL` / `FIREBASE_PRIVATE_KEY` /
      `FIREBASE_PROJECT_ID` (FCM push — the EF mints its own OAuth token). The
      `SUPABASE_*` vars are injected automatically.
- [ ] `[functions.engine]` block (`verify_jwt = false`) present in `config.toml`
      (per-app, not vendored) so the function deploys
- [ ] `supabase functions deploy engine` run — see `engine_architecture.md §21`.
      Ratings (OpenSkill) and notifications (FCM) run inside the shared
      framework; there is no `update-ratings` or `refresh-fcm-token` function or
      FCM-token cron job.
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
