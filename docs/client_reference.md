# Eigen Client — Reference

The reference for the **client side** of the Eigen engine: the Flutter app
shell, the transport that talks to the server, the Dart half of a game's rules,
and everything involved in shipping a real app. Its companions live in the
`eigen-server` repo — [`architecture.md`](../../eigen-server/docs/architecture.md)
(how the server works) and
[`building_a_game.md`](../../eigen-server/docs/building_a_game.md) (the
authoritative TypeScript rules contract). Read those for the server; read this
for the client.

This describes the client **as built**. Exact widget and provider signatures
live in the code and are not repeated here; what this captures is the design,
the contracts, and the setup that isn't discoverable by reading the source.

The client is one Flutter package, **`eigen_flutter`** — transport, state, and
presentation — layered by directory rather than by pubspec. It consumes
**`eigen_api`**, the REST client generated from the server's `openapi.json`, as
a path dependency; those generated types are the data model directly, with no
hand-written mirrors. Each game supplies a Dart **`GameRules` twin** for
optimistic preview and rendering.

### What a game app depends on

A game app depends on **`eigen_flutter` alone** and imports **only its barrel**,
`package:eigen_flutter/eigen_flutter.dart`. It never depends on `eigen_api`
directly and never reaches into `eigen_flutter`'s file layout.

That matters for two reasons. `eigen_api` is a *build artifact* —
`tool/generate_api.sh` deletes and rewrites it wholesale — so an app depending on
it would be pinned to another repo's codegen output at a path inside that repo's
package directory. And the framework needs one public surface it can evolve
behind; deep imports make every internal file layout an accidental contract.

So the barrel re-exports the wire vocabulary a game renders from — `GameStatus`,
`Outcome`, `OutcomeResultEnum`, `Player`, `Seat`, `Frame`, and the rest. It
lists them explicitly rather than
exporting `eigen_api` wholesale, so the generated `*Api` classes and their Dio
plumbing stay out of an app's namespace: **naming a type is part of the contract,
calling the server is not.** `test/core/architecture/api_isolation_test.dart`
enforces both halves.

---

# Part I — Transport

## 1. Session, requests & errors

- **Auth is Firebase.** Google and Anonymous sign-in are implemented;
  `linkWithCredential` upgrades a guest to a permanent account, preserving the
  uid, so every game, rating and friendship carries over with no data migration.
  Every request sends the Firebase ID token as `Authorization: Bearer <token>`;
  WebSocket upgrades send it as `?token=` (browsers can't set headers on an
  upgrade). Tokens refresh on the Firebase SDK's schedule; the client attaches
  the current one per request.
  *(**Apple Sign-In is scoped but not wired** — there is no `sign_in_with_apple`
  dependency yet. See `todo.md` in the server repo.)*
- **The API client is generated** from the vendored `openapi.json`. Client routes
  live under `/api/engine/*`; the configured base URL is an **origin only**
  (scheme + host, no path, no trailing slash) because every generated route
  already carries its own prefix. The one non-generated piece is the frame
  stream (§2), which is hand-written.
- **Errors** are `{ error, code? }`, and `code` is a **generated enum**
  (`ErrorCode`), so `humanize` switches over it exhaustively — adding a code
  server-side fails the client build until copy exists. `engineCall` converts a
  server-reported failure into `EngineException`; a failure with *no* response
  propagates as the underlying `DioException`, because "the server said no" and
  "the outcome is unknown" mean different things to a state-changing command.
- **Wire enums are closed sets.** Generated enums carry no `unknown` sentinel and
  parse strictly, so adding a member to any of them — `GameStatus`, `ErrorCode`,
  `GameAccess`, seat type — is a breaking change needing a schema-version bump.
  `test/shared/api_contract_test.dart` pins the sets so drift fails loudly.
  *(Deliberately not `@JsonKey(unknownEnumValue:)`: the client does not degrade
  gracefully on an unknown value, it refuses to build. §25 explains why that
  trade is the right one here.)*
- **Lists page by keyset cursor**, not offset: the cursor is the previous page's
  last sort value. These lists change while they are being read, and an offset
  would show the same row twice after a single insert.
- **Avatar URLs may be relative.** With the default worker-served setup the
  server returns `/avatars/{uid}?v=<ts>`; with a public bucket domain it returns
  an absolute URL. `resolveAvatarUrl` resolves either against the API origin, and
  every seat rendering routes through `PlayerAvatar` so that resolution lives in
  one place. The `?v=` cache-buster means `cached_network_image` refreshes on
  re-upload with no manual invalidation.

## 2. The frame stream

A game has **one WebSocket for its whole lifetime** (`/api/engine/games/{id}/socket`),
opened before the game starts. Over it the client receives:

- **Roster snapshots** pre-game — unversioned and idempotent, pushed on every
  lobby change. A reconnect just gets the current one.
- **A `sync`** on a mid-game open — `{ version }`, the newest committed version
  at the moment the socket opened. From v0 the roster is frozen, so this is what
  moves; it is what lets a client reconcile in one step instead of guessing.
- **Versioned frames** from v0 — each is one seat's projected observation at one
  state version (`{ version, data, pending_players, deadline, player_times,
  outcomes?, ratings? }`).

Frames are **strictly serial with no gaps**. The client tracks the last version
it holds and reconciles against the `sync`, which costs a request only when it
has to:

- **Nothing held yet** (a cold open, mid-game) — fetch just that one version. A
  cold load snaps to the present rather than replaying the game.
- **Already current** — no request at all. This is the common reconnect on a
  flaky connection, and is why the server states its version rather than leaving
  the client to poll.
- **Behind** — fetch exactly the missing span via **`GET /games/{id}/frames?from=&to=`**
  and emit it in order *before* the frame that revealed the gap, so the game
  animates through every transition it missed.

The same range-fetch endpoint serves finished-game **replay** (the server
re-projects from its immutable log) — replay is just the whole range rather than
a missing slice. Reconnection is therefore always sound: reconcile against the
server's stated version, never guess.

A command's own frame also rides its HTTP response (`CommandAccepted.frame`) and
is fed into the same version-deduped pipeline, so whichever copy arrives second
is dropped. That matters less for latency than it looks — the socket terminates
at the same Durable Object and is written first — but it is what makes the
socket-less paths work: a freshly created solo game has no socket yet, and a
move submitted while the socket is mid-reconnect would otherwise render nothing.

## 3. The frame & animation model

Animation is the presentation of **frame transitions**. Three guarantees:

1. **You see every frame, in order.** Every move — yours, an opponent's, a bot's,
   a timeout resolution — arrives as its own frame, so "animate the change between
   the previous frame and this one" is sound for *all* transitions. The one
   exception is a cold (re)load, where the stream starts at the latest frame with
   no predecessor (rule 3).
2. **The observation tells you what happened — don't diff frames.** Frame diffing
   can't recover causality (a hidden move with no visible footprint; two causes
   with the same footprint; a composite resolution the diff collapsed). Instead
   the game's `computeObservation` receives the transition's `cause` and embeds
   each seat's permitted view of it into that seat's `data` (a `lastMove` /
   `events` field, shaped for your animation). Visibility is per-seat because the
   embedding happens inside the projection, and replay frames carry the same cues
   — one animation pipeline serves live play and replay.
3. **Animate a cue only when you rendered its predecessor.** A cue describes a
   transition. On a cold load or stale rejoin you get a frame whose predecessor
   you never rendered — show the cue as static "last move" info (a highlight), not
   an animation. Keep the last rendered `version` in widget state; play the
   entrance animation only when the incoming frame is its direct successor.

### Optimistic preview (optional latency hiding)

A turn-based round trip is usually well under a second, so latency hiding is
**game-owned** — the transport never predicts game state, it only reports how a
submit resolved. Two layers:

- **Outcome-independent feedback** needs no bookkeeping: lift the piece on tap,
  slide it, play the sound in local widget state, resolved when the server frame
  lands. `GameContentContext.actionPending` already marks the in-flight window.
- **Optimistic rendering** pairs the Dart twin's `previewAction` with the
  `ActionSubmitResult` that `onAction` returns. Compute the predicted observation
  locally and render it while the request is in flight; the result tells you what
  the stream will do:
  - **`committed`** — the confirming frame is guaranteed to be the *next* frame
    (versions are serial, so nothing commits in between); clear the prediction
    when it arrives.
  - **`rejected`** — the move did not commit and no frame is coming; revert (the
    board snaps back). Infra has already surfaced the error.
  - **`unconfirmed`** (the request failed in transit) — the server may or may not
    have committed it; revert, and if it *did* commit, its frame arrives over the
    socket and re-applies.

  `previewAction` returning null means "don't predict this move" — required for
  moves whose result depends on hidden information (a combat resolution, a reveal,
  a deck draw); those render server-driven. Predict only the actor's own moves;
  opponents' moves always arrive as server frames.

## 4. Player identity

The transport resolves all seat identities before the game screen renders, so
game code gets non-nullable identity — no null checks or loading states.

- Identity comes from `GET /api/engine/players?ids=` (batch, public identity:
  username, display name, avatar, anonymity — never email), warmed by a
  client-side persisted cache (§12). Game rows carry no denormalized identity,
  so a renamed user is correct everywhere on the next fetch.
- For a **finished game whose participant was deleted**, the server anonymizes the
  seat (the roster keeps the seat, id nulled); the client renders a **synthetic
  identity** ("Deleted User", `player_{index}`) and sets `GamePlayer.isDeleted`.
  **`isDeleted` is the guard** — never inspect the synthetic `Player.id`, which
  exists only to give the seat a distinct widget key and is not a real user id.
- **Game identity vs social identity.** Seat identity covers humans *and* bots and
  is the right tool in game screens and lobby cards. Social features (friend
  search, requests) are human-only and never surface bots. Don't branch on player
  type to decide whether to show identity — show it uniformly; use the seat's
  `type` only where game rules must distinguish a bot seat.
- **The viewer case.** A non-participant replaying a public finished game has no
  seat — `MySeat` is a sealed `Seated(index) | Viewer`, so viewer checks simply
  never match "is it my turn". Read `mySeat.indexOrNull` where a null is the right
  answer for a viewer.
- Per-game **roles** (host, team, dealer) are not a transport concept — they live
  in the game's observation JSON, shaped by `computeObservation`.

**Shared identity widgets** (`lib/shared/widgets/`, exported from the barrel where
a game needs them):

| Widget | Use |
|---|---|
| `PlayerAvatar` | One seat's avatar — cached network image, initials/person fallback, optional active border, relative-URL resolution. `onTap` optional; leave it unset inside a `ListTile` (the tile's own ink covers the row). |
| `OverlappingAvatars` | The overlapped row used on game/lobby cards. |
| `PlayerProfileSheet` | Modal profile — identity, ratings across pools, friendship actions (humans only). Guard with `isDeleted` before opening. |
| `EmptyStateView` | The illustrated empty state shared by all list screens (home, lobby, history, friends, requests). |
| `StatusBanner` | The slim full-width banner primitive behind the offline / reconnecting banners. |

## 5. Timing & clocks

Timing is server-authoritative; the client only *displays* it. Each frame carries
the true `deadline` (epoch ms, or null when untimed) and, in budget mode, the
per-seat `player_times` banks.

- **Measure against server time, not the device clock.** `ServerClock` tracks the
  offset from the `Date` header every response already carries, and
  `deviceTimeFor()` converts a server timestamp into device time so a countdown
  ticks correctly on a device whose clock is minutes out. Deadlines are absolute
  epoch-millisecond **server** timestamps — the same value the server's own
  expiry alarm fires on — so display and expiry cannot diverge.
- **Only one bank drains at a time.** Budget mode permits a single pending seat,
  so the turn deadline and the acting seat's bank are the same quantity.
- **The soft margin nudges honest players to submit early.**
  `softDeadlineMarginFor(window)` returns `min(1s, 25% × window)` — capped as a
  fraction so a short window (a 3 s reaction phase) isn't swallowed. `TurnCountdown`
  subtracts it so the displayed countdown reaches zero slightly early, and
  `BudgetClock` uses it only to raise a "submit!" cue: a budget clock stays
  numerically truthful, because subtracting a margin would make a chess-style
  clock visibly snap back up on submit. Display only, never enforcement.
- **The server's grace window is the server's.** `kServerDeadlineGrace` (750 ms)
  records the server's constant for reference; the client does not apply it to
  anything. The soft margin above is what keeps an on-time move from needing it.
- **Expiry is the server's.** When the clock hits zero the client shows "time's
  up" and waits for the timeout frame. There is **no client expiry nudge** — the
  Durable Object's alarm is the timer, which is the main simplification the
  Cloudflare server bought over the database-backed design.

`TimingContext` (on `GameContentContext.timing`) carries `clock`, `deadline`,
`playerTimes`, and `windowMillis`, plus `isTimed`, `deviceDeadline` and
`remaining`. Two headless builders render from it, so a game can place clocks
anywhere:

| Widget | What it owns |
|---|---|
| `TurnTimerBuilder` | A 1 s ticker toward a deadline, self-cancelling at zero. Hands `Duration remaining` to a `builder`. Pass `isPaused` (typically `ref.watch(isOfflineProvider)`) to freeze the display without losing wall-clock position. |
| `PlayerTimerBuilder` | One seat's bank — live drain for the acting seat, static for the rest. Hands `(int remainingMs, bool isActive)` to a `builder`. |

The infra-owned shells `TurnCountdown` (per-action) and `BudgetClock` (a row of
per-seat cells) wrap those and handle the offline pause automatically; the game
screen picks between them by timing mode. Use the builders directly only when a
game needs custom placement (chess clocks beside captured pieces; an N-player
game showing only the active seat).

**Server-seated bots require a timed game.** The create/solo UI must require a
turn or budget clock whenever a bot is seated by the server: bot dispatch is
single-attempt, so the turn deadline firing the server's alarm is the only thing
that resolves a bot which never moves. The rule is scoped to *server* seating on
purpose — a client-driven bot has no dispatch to fail, so the deferred
offline-solo path stays free to be untimed.

---

# Part II — Building a game's client half

The server repo's `building_a_game.md` is the authoritative guide to the
**TypeScript** rules. This part is its Dart mirror: what a game implements on the
client, and what infra hands it.

## 6. The two containers

A game ships two same-shaped registries, one per language:

- a **TypeScript `GameModule`** — `GameRules` units keyed by `schema_version`,
  each bundling the payload schemas and the authoritative hooks;
- a **Dart `GameModule`** — the same keys, client units (payload codec,
  legality, optimistic preview, rendering) plus the version-independent
  creation/about UI.

**A version is a self-contained unit and the framework owns all dispatch.** Every
screen resolves the game's `schema_version` and uses that unit; game code never
branches on version. Shipping a breaking change means adding a `v2` unit on both
sides (reusing unchanged pieces by import), not editing `v1`.

| Member | TS `GameRules` | Dart `GameRules` |
|---|---|---|
| `initialState`, `applyAction`, `applyLifecycle`, `computeObservation` | ✅ authoritative | — (the client consumes observations) |
| `schemas` (payload contracts) | ✅ | ✅ as the codec: `parseConfig` / `parseObservation` / `parseAction` / `serializeAction` |
| `isValidAction` | — (`applyAction` *is* the check) | ✅ UX-only transcription of its legality half |
| `previewAction` | — (`applyAction` is the truth) | ✅ required; the game's own optimistic projection (null ⇒ server-driven) |
| `ratingPool`, `botSeatable` | ✅ enforced | ✅ display-only twin — keep in sync |
| `buildContent` | — | ✅ client-only |
| `botActions` (bot brains) | ✅ server-side | — (**client-side local bots are deleted**) |

Every "keep in sync" is enforceable, not aspirational: shared JSON fixtures run
against both units and fail a test on divergence (§9).

## 7. The Dart `GameRules` unit

```dart
class MyGameRulesV1
    extends GameRules<ObservationData, ActionData, GameConfigData> {
  const MyGameRulesV1();

  // Codec — the Freezed mirror of the TS unit's schemas.
  @override GameConfigData parseConfig(Map<String, dynamic> j) => GameConfigData.fromJson(j);
  @override ObservationData parseObservation(Map<String, dynamic> j) => ObservationData.fromJson(j);
  @override ActionData parseAction(Map<String, dynamic> j) => ActionData.fromJson(j);
  @override Map<String, dynamic> serializeAction(ActionData a) => a.toJson();

  // Legality — the transcribed legality half of the TS applyAction.
  @override
  bool isValidAction({
    required ObservationData obs,
    required List<int> pending,
    required ActionData data,
    required int playerIndex,
    required GameConfigData config,
  }) => /* boundary / occupancy / ownership checks only */ true;

  // Optimism — or null to stay server-driven.
  @override
  ObservationData? previewAction({ /* same parameters */ }) => null;

  @override
  Widget buildContent(GameContentContext context) =>
      MyGameContent(rules: this, content: context);

  // Display-only twins of the TS predicates.
  @override String? ratingPool(RatingPoolArgs args) => null;
  @override bool botSeatable(BotSeatableArgs args) => true;
}
```

Notes that are easy to get wrong:

- **Do not re-check whose turn it is** in `isValidAction` for the sequential
  case — the caller has already gated on `pending`. Check *move* legality.
  Games with interrupt actions (a "Nope" window) use `pending` to tell a
  main-turn action from an interrupt.
- **`playerIndex` is passed to every game** even when unused, so the contract
  stays uniform. Chess needs it (piece ownership); tic-tac-toe doesn't.
- **The rules unit carries no player metadata.** Player counts are declared on
  `GameCreationSpec`; identities arrive via `PlayersContext`.
- **Turn-gating, game-over and winner derivation are infra facts**, surfaced via
  `frame.pendingPlayers`, `gameStatus`, and `outcomes`. Never re-derive them.
- **Infra hands widgets no rules access.** The unit passes `this` (or just the
  members a widget needs) into the content widget it builds, so the dependency
  stays explicit.

### `GameContentContext` — what `buildContent` receives

One object rather than a long parameter list, so adding infra data later never
breaks every game's signature.

| Member | Meaning |
|---|---|
| `config` | The parsed config, immutable for the whole game. Cast to your type. |
| `frame` | The per-event snapshot: `observation`, `pendingPlayers`, `version`, `timing`. |
| `gameStatus`, `outcomes` | Lifecycle status; per-seat results (empty until finished). |
| `actionPending` | True while a submit awaits its confirming frame — disable input on it. |
| `onAction(json)` | Submits a move; returns `Future<ActionSubmitResult>` (§3). Never throws — infra has already surfaced any error. |
| `onInvalidAction()` | Call when `isValidAction` rejects a tap. **Infra owns the haptic** — never import `flutter/services.dart` to pick one yourself. |
| `playersContext` | Resolved identities; `mySeat` delegates to it. |
| `isReplay` | True when stepping a finished game frame by frame. |

During replay `gameStatus` is `finished` for every frame and `outcomes` is
populated only on the final frame, so a win banner appears at the end rather than
mid-replay. A game never *needs* `isReplay` to stay correct (the frame is a real
observation and `onAction` is inert) — it exists for replay-only presentation.

### The action payload

The engine defines **no** game-specific action type, exactly as it defines no
observation type. You own the shape, in three places that must agree: the human
tap, the server bot's JSON, and the TS `applyAction` that consumes it. Keep it
minimal — it is *only* "what the move is". Infra supplies the seat, version, RNG,
and config as separate inputs, so never put them in the payload.

`serializeAction` is the **single** place a typed action becomes JSON, which is
what keeps the producers from drifting.

## 8. Creation UI — `GameModule`

```dart
class MyGameModule extends GameModule {
  const MyGameModule();

  @override
  Map<int, GameRules> get versions => const {1: MyGameRulesV1()};

  @override
  GameCreationSpec get creationSpec => const GameCreationSpec(
    minPlayers: 2,
    maxPlayers: 2,
    timingConfigs: {
      'Untimed': UntimedConfig(),
      'Rapid': PerActionConfig(minSeconds: 60, maxSeconds: 600,
                               presets: [60, 120, 300, 600]),
    },
  );

  @override
  Widget? buildCreationConfig({required ValueChanged<Map<String, dynamic>> onChanged}) => null;

  @override
  Widget buildRules(BuildContext context) => const MyGameRulesPage();
}
```

- **`versions` keys are sparse.** `supportsSchema` is key membership, not
  `<= latest`, so a drained-and-retired old version is correctly unsupported.
  New games are created at `latestSchemaVersion`.
- **`timingConfigs` keys become segmented-button labels**, in insertion order.
  `PerActionConfig` renders presets + a slider; `BudgetConfig` adds an increment
  slider. Floors are enforced on both sides (`kMinTurnSeconds` 30 s,
  `kMinBudgetSeconds` 120 s).
- **`BudgetConfig` is only valid for strictly sequential games** — the server
  rejects a hook envelope with more than one pending seat in a budget-timed game
  as a game bug. If any phase has multiple pending seats, use a per-action mode
  (or a hook `turn_seconds` override) for it.
- **`playersForConfig`** overrides the range when it depends on a creation-time
  choice (a party game where the host picks 4 or 6 and min == max).
- **`buildCreationConfig`** returns a widget for game-specific options. It calls
  `onChanged` on every edit; the dialog stores the latest value in a plain field
  (no `setState`) and sends it at submit.
- **`buildRules`** returns non-scrolling how-to-play content — the About page
  supplies the scroll container and chrome.
- **`rated` is a validated assertion.** The client computes it from the Dart
  `ratingPool` twin plus its guest status and sends a concrete value; the server
  recomputes and **rejects a mismatch (422)** rather than coercing. That is what
  catches twin drift and forged clients, so the twins must agree.

## 9. Testing a game's client half

**Twin-drift fixtures** are the net. One set of shared JSON fixtures per schema
version runs against *both* units — the TS runner drives `applyAction` +
`computeObservation`, the Dart runner drives the codec, `isValidAction`, and
`previewAction`. `expected.observation` is the shared behavioural anchor both
sides are compared through.

The Dart half rides `flutter test` via
`package:eigen_flutter/testing/twin_fixtures.dart`
(`loadTwinFixtureSuites` + `runTwinFixtureCase`).

Three things the fixtures are strict about:

- **Fixtures use the wire shape, not Dart field names.** With
  `field_rename: snake`, the key is `action_count`, never `actionCount` — and the
  TS schemas must use the same keys. The fixture is what pins this.
- **The Dart observation type needs value equality** for the observation
  comparison. Freezed gives it; a hand-written type must override `==`/`hashCode`.
- **Grow the suite with the rules.** Cover at minimum one legal move (with its
  expected observation), one illegal move, one game-ending move, and one case per
  `ratingPool` / `botSeatable` branch.

Beyond that, plain unit tests against the rules unit for helper logic, and the
engine's own suites for everything infra.

---

# Part III — The app shell

## 10. Package layout

```
eigen-flutter/
├── openapi/openapi.json     # vendored snapshot of the server spec
├── tool/generate_api.sh     # regenerates eigen_api from that snapshot
├── packages/eigen_api/      # GENERATED — never hand-edited
└── lib/
    ├── eigen_flutter.dart   # the public barrel (§"What a game app depends on")
    ├── app_runner.dart      # runEngineApp(...) — the entry point
    ├── core/
    │   ├── api/             # Dio + auth interceptor, engineCall, the socket,
    │   │                    #   ServerClock, avatar-URL resolution
    │   ├── config/          # AppConfig (Branding + EngineConfig)
    │   ├── game/            # the game contract: GameModule, GameRules,
    │   │                    #   GameFrame, PlayersContext, TimingContext,
    │   │                    #   MySeat, GameCreationSpec, timing constants
    │   ├── analytics/ notifications/ updates/ review/ connectivity/
    │   ├── storage/ theme/ navigation/ errors/ utils/ startup/
    ├── features/            # about auth game home profile rating settings social
    │   └── <feature>/{data,providers,presentation}
    ├── shared/{data,providers,widgets}
    └── testing/             # the Dart half of the twin-fixture runner
```

The layering rule is enforced by a test, not convention:
`test/core/architecture/api_isolation_test.dart` restricts `package:dio` and the
six generated `*Api` classes to `core/api/`, the feature `data/` layers, and
`shared/data/`. Generated *models* may be used anywhere — they are the domain
vocabulary. What is confined is the **capability to make a request**, not the
types that come back. That test is what made folding transport into this package
safe after the separate pure-Dart package was dropped.

A consuming app is a standard Flutter app with the game under `lib/game/`:

```
my_app/
├── pubspec.yaml             # depends on eigen_flutter (path, until published)
├── lib/
│   ├── main.dart            # ~30-line entry: runEngineApp(module, config, …)
│   ├── env/                 # envied-generated Env
│   ├── firebase_options.dart
│   └── game/
│       ├── game_module.dart # versions map + creation/about UI
│       └── v1/              # one folder per schema_version
├── test/game/twin_fixtures_test.dart
├── android/ ios/ web/ …
├── assets/icon/             # icon.png + icon_foreground.png
└── fastlane/                # Fastfile + Appfile
```

The `v1/` folder is a **convention, not enforced** — the contract is the
`versions` map. But mirroring the layout across both languages is what makes a
version bump mechanical: a new folder in each tree plus one map entry each.

**Fonts need nothing per app.** The engine bundles Inter as a package font (all
nine weights, declared under `fonts:` in its own pubspec), so Flutter includes it
in every consuming app automatically and it renders offline from the first frame
— no `google_fonts`, no runtime fetch. To change the typeface, add the new
family's weights to the engine's `fonts/` and update the one constant in
`AppTheme`.

## 11. App startup

`AppStartup` wires the singletons the shell depends on, in a fixed order so no
initial event is missed:

1. Listen to auth state (`listenManual`, before anything can emit).
2. **Register the notification navigation listener *before* calling
   `initialize()`** — the terminated-state tap arrives on a broadcast stream, so
   a listener attached after init misses it.
3. Keep the native splash up until auth resolves; if authenticated, also await
   the profile cache restore, **capped at 2 s**. SQLite resolves in ~5 ms, so the
   cap only fires on a first-ever launch with no cache and no network — in which
   case `FlutterNativeSplash.remove()` still runs in `finally` and the home
   screen opens with a loading profile. The app is never stuck behind the splash.
4. An `AppLifecycleListener` re-checks OS notification permission and polls for
   an Android in-app update on every resume.

On **sign-in** the same handler does four things, all fire-and-forget so none of
them delays first paint: identify the user to analytics, tag the account as guest
or registered, register this install for push, and pre-warm the profile and bot
catalog. Registration is driven by *auth state* rather than by the notification
service's one-time init, because the row maps a **user** to a device — an
in-session sign-in or account switch must re-register.

The splash is **infra-owned**: a game never calls `FlutterNativeSplash.remove()`.

## 12. Local persistence

**Goal:** eliminate cold-start spinners for data that is already known and rarely
changes — first paint shows real data, background refreshes update silently.

A single on-device SQLite database (`riverpod.db`, via `riverpod_sqflite`) stores
persisted provider state as JSON, opened once at startup and shared. Persisted
providers **race** their SQLite restore against the network fetch rather than
sequencing them: `persist()` is called *without* awaiting, and an internal
`didChange` guard stops a slow cache read from overwriting a fresher network
result.

| Provider | Persisted | Why |
|---|---|---|
| current user profile | yes | Own profile; cold-start UX |
| player-info cache (per id) | yes | Public identity; kills per-seat spinners and keeps the batch `players?ids=` endpoint warm |
| friends | yes | Social list; stale-while-revalidate |
| bot catalog | yes | Deployment-global reference data; readies the "Add bot" picker |
| ratings, active games | **no** | Live data — staleness would be misleading |

Two disciplines make this safe:

- **`destroyKey` is per provider, not global.** Bump the individual provider's
  key when *its* model's persisted shape changes incompatibly; old entries are
  discarded and refetched. Sharing one key would mean a profile change wipes the
  friends cache. There is no incremental JSON migration — this is the only path.
- **Clear on sign-out and account deletion.** `deleteUserData(uid)` wipes every
  user-scoped key (`profile_{uid}`, `friends_{uid}`, …) and must run **before**
  the auth session ends, since after deletion the credentials are gone. Cache
  entries never expire on their own, so this explicit eviction is the only
  eviction. The **player-info cache is deliberately not cleared** — player
  identity is public, and a second account on the same device benefits from it.

The keys live in one place (`core/storage/`) rather than beside their providers,
which also breaks a circular import between auth and profile.

## 13. Connectivity & offline UX

Connectivity is infra-owned — game code never watches it. Two banners, both built
on `StatusBanner`, both animating their height so the layout slides rather than
jumps, and both pushing content down rather than overlaying it:

- An **offline banner** on shell screens when the device reports no network.
- A **reconnecting banner** on the game screen when offline *or* the game
  stream/observation is erroring *and* the game is non-terminal. It lives in its
  own leaf `ConsumerWidget` so a connection blip rebuilds the banner, not the
  whole game tree.

Two subtleties worth keeping:

- **Interface availability is not internet reachability.** `connectivity_plus`
  reports "online" on a captive Wi-Fi with no upstream. So the error arm matters
  as much as the offline arm, and the real recovery signal is the stream
  re-syncing (§2), not the connectivity flag.
- **Stale data beats an error screen.** The game screen renders from
  `asyncValue.value` whenever it is non-null — which covers `AsyncError` carrying
  a previous value — so the board stays visible while the banner communicates the
  reconnecting state. The hard error state only appears on a cold-start failure
  with no data ever received.

On the offline → online transition the game screen invalidates its providers
immediately, bypassing Riverpod's retry backoff.

## 14. Navigation

A shell with indexed-stack branches, and full-screen routes above it:

```
/home /lobby /history /social /about /settings   — shell branches (drawer-switched)
/game/:gameId   /join/:code   /profile            — full-screen, above the shell
```

- Branch screens are top-level destinations; Back exits the app (branches switch
  via the drawer, not Back). There is no `PopScope` intercepting it.
- `/game` is always reached by a push, so Back returns to the source screen
  (home/lobby/history) with the predictive-back peek.
- `/join/:code` is a transient spinner that resolves the short code and
  `pushReplacement`s into the game, so Back from the game never lands on a stuck
  spinner. On error it `go`es home — safe for both in-app entry and a deep-link
  cold start where no shell is in the stack.
- Deep links (`/join/{code}` from a share, or a push's deep link) route through the
  same join/game paths.

Use `go` for auth redirects and branch roots (replaces the stack), `push` for
anything Back should undo, `pushReplacement` for transient screens.

Three things that are easy to delete by accident:

- **`android:enableOnBackInvokedCallback="true"`** in `AndroidManifest.xml` opts
  into the Android 14+ predictive back API. Its absence silently disables
  predictive back for every user on 14+.
- **The `onException` handler** redirects any unmatched or malformed route to
  `/home`. Without it, an iOS Universal Link the OS hands to the app that matches
  no declared route (a `/terms` URL, say) throws a `GoException` that surfaces as
  a crash.
- **`NotificationNavigation.navigateFromNotification`** pushes for overlay
  prefixes (`/game/`, `/join/`) and `go`es for shell branches — mirroring the
  route structure, so Back after a notification tap returns where the user was.
  A new overlay route must be added to its prefix list.

Terms/privacy links open with `LaunchMode.inAppBrowserView` (Safari View
Controller / Custom Tabs) specifically to bypass Universal Links interception —
see §21 for why they are also hosted on a *different* domain from the app.

## 15. Push notifications (FCM)

Push is infra-owned; game code never registers anything. On startup the service:

1. Creates the Android notification channels — three, so users get per-category
   system-level control:

   | Channel | Importance | iOS level | Sent for |
   |---|---|---|---|
   | `your_turn` | High | `timeSensitive` | A seat newly becomes pending |
   | `game_invites` | Default | `active` | A friends-access game is created |
   | `social_notifications` | Low | `active` | Friend request / accepted |

   `your_turn` is also the manifest default channel, so a system-delivered
   background notification with no explicit channel lands somewhere sensible.
2. Enables foreground banners (iOS presentation options +
   `flutter_local_notifications`).
3. Requests OS permission once, gated by a persisted first-launch flag.
4. Forces FCM registration with `getToken` (passing `vapidKey` on web), then reads
   the **Firebase Installation ID (FID)** and registers it with
   **`PUT /api/engine/me/devices { fid, platform }`**. The token result is
   discarded — the FID is the stored identity, because FCM v1 deprecated the
   registration-token target. It re-registers on `onIdChange`.
5. On a foreground message, shows a local banner — **except** a `your_turn` push
   for the game currently on screen (it reads the router's current URI and
   suppresses a banner for a matching `/game/{id}`). Background delivery is
   unaffected; the OS renders those directly.
6. Routes taps via the deep link on the message (`/game/{id}`, `/social`).

**Sign-out** calls `DELETE /api/engine/me/devices/{fid}` (scoped to the caller, so
a device already reassigned to another account is left alone) and clears the local
guard. It deliberately does **not** delete the Firebase installation — that would
reset Crashlytics/Analytics identity — and does not drop the FCM registration,
which wouldn't re-establish until the next process start and would break
same-session re-sign-in. Account deletion removes the device rows server-side.

The **background handler** must be a top-level `@pragma('vm:entry-point')`
function that re-initialises Firebase and does nothing else — the OS renders the
notification from the payload. It is passed into `runEngineApp` by the app,
because it needs the app's own `DefaultFirebaseOptions`.

**The category field is strict on purpose.** An unknown or missing `category` in
the data payload throws rather than falling back to a default channel: a silent
fallback would hide a misconfigured server-side send until a user reported
missing notifications.

Delivery is best-effort and there is no retry — the game state is the truth and
the app catches up on open, so the client must never depend on a push arriving.

### The Android notification icon

Android API 21+ ignores colour in notification icons — it composites the alpha
channel against its own tint. Using the full-colour launcher icon renders a solid
white box. The correct asset is a **monochrome silhouette vector drawable** at
`android/app/src/main/res/drawable/ic_notification.xml`, referenced in three
places: the manifest's `default_notification_icon` meta-data (background and
terminated delivery), `AndroidInitializationSettings` (foreground banners), and
`AndroidNotificationDetails(icon:)` (per-notification, for consistency).

It is a `<vector>`, so no per-density variants are needed — and
`flutter_launcher_icons` does **not** generate it. This is a one-time,
hand-maintained, **per-app** asset: replace it when the app rebrands.

## 16. Analytics & crash reporting

Both are **infra-owned** — a game never imports a Firebase package or fires an
event. Firebase itself is mandatory: `runEngineApp` initialises it before
anything else, so every deployment runs it.

`AnalyticsService` is an abstract interface over primitives (`String`, `int`,
`bool`) that never imports `features/` types — call sites convert enums to
strings. The Firebase implementation sits behind a keepAlive provider. The point
of the interface is not swappability (there will only ever be Firebase); it is
that call sites don't depend on Firebase and the service is trivially faked in
tests.

**Crashlytics** is wired before `runApp`, both arms, so no crash window exists at
startup:

```dart
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
PlatformDispatcher.instance.onError = (error, stack) {
  FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  return true;
};
```

`FlutterError.onError` catches framework errors (build failures, assertions);
`PlatformDispatcher.onError` catches isolate-level errors that escape the
framework. **Screen tracking** is a `FirebaseAnalyticsObserver` registered on the
GoRouter instance — one `screen_view` per route transition, no per-screen code.

Events fired automatically: `game_created`, `game_started`, `game_finished`,
`forfeit`, `join_by_code`, `friend_request_sent`, `friend_accepted`. Identity is
`identify` on sign-in / `reset` on sign-out, plus an account-type tag so every
metric segments by guest vs registered.

Two implementation rules that keep these honest:

- **Side effects use `listenManual` in `initState`, never `ref.listen` in
  `build`** — so they don't re-fire on widget rebuilds.
- **Fire only on a *witnessed* transition.** `game_started` requires a previous
  status of `waiting`/`ready`, so opening an already-active game doesn't
  re-count. `game_finished` requires a previous **empty** outcomes list, which
  covers both re-fire paths: reopening a finished game from History (previous is
  null) and an app-resume reload (Riverpod's `AsyncLoading` carries the previous
  non-empty value). The **same guard** gates the win haptic and the in-app review
  counter, so revisiting an old win never inflates either.

Note Firebase Analytics rejects raw `bool` parameters — booleans go as `int` 0/1.

## 17. Guests

Anonymous sign-in gives a real uid and a real (ephemeral) account, so a visitor
can play immediately. Guest capability is deliberately narrowed **server-side** —
the client's job is only to not offer what will be refused:

- Guests **may** play, including solo vs bots (which comes out unrated). Solo is
  a guest's first-run experience and is *not* gated.
- Guests **may not** create friends-access games, join rated games, or use social
  features at all.
- The Social drawer destination stays **visible but disabled** rather than hidden,
  and `/social` is redirected home in the router as a deep-link backstop. Rated
  lobby games show with a disabled join button. Visible-but-disabled teaches what
  signing up buys; hiding teaches nothing.
- Settings shows a "save your progress" upgrade card, because **inactive guests
  are swept server-side** after a period of inactivity.

**Upgrade preserves the uid.** `linkWithCredential` converts in place, so games,
ratings and friendships carry over with no migration; the provider's display name
and avatar overwrite the guest's while the stable username handle survives. If the
chosen account already belongs to a registered user the link fails, and the
controller **switches into the existing account** instead — clearing the abandoned
guest's local data and device registration first, exactly as sign-out does.

A long-dormant guest may have been purged server-side. The client treats "valid
token, empty data" as automatic re-provisioning (the server creates a fresh guest
row on the next request), not an error.

## 18. Haptics, updates & review

**Haptics** are infra-owned — a game never imports `flutter/services.dart` or
picks a feedback style. Three moments fire from the game screen: `lightImpact` on
a submitted action (optimistically, before the request), `heavyImpact` on a win
outcome, and `selectionClick` via the `onInvalidAction` callback the game calls
when `isValidAction` rejects a tap. Centralising the choice is what makes
intensity a single future setting rather than a scattered one.

**In-app updates (Android)** run on resume via Play Core. If an *immediate*
update is allowed and no game is active, the full-screen update runs; if a game is
active it is **skipped and retried next resume** — never silently downgraded to a
flexible update, and never interrupting a game. A *flexible* update downloads in
the background and surfaces a "new version ready — Restart" snackbar. The
mid-game gate reads the current route (`/game/` sits outside the shell navigator,
so a prefix check is reliable). The notifier exposes state rather than showing the
snackbar itself, because it sits above `MaterialApp` and can't resolve a
`ScaffoldMessenger` — the shell scaffold listens and shows it. iOS has no
equivalent; the check returns early.

**In-app review** requests the OS prompt every 5 lifetime wins (persisted in
`SharedPreferences`), fire-and-forget so a slow store round-trip never delays the
outcome UI. The OS enforces its own quota (~3×/year) silently, so no
application-level gate beyond the counter is appropriate. The review dialog
**never appears on simulators or debug builds** — test through TestFlight or an
internal track.

---

# Part IV — Shipping an app

## 19. Environment & configuration

An app's runtime configuration is one `AppConfig` passed to `runEngineApp`:
`Branding` (app name, seed colour) plus `EngineConfig` (the injected runtime
values). Nothing is read from `Env` inside the framework — the app owns its env
plumbing and hands values in, which is what lets the framework stay app-agnostic.

`.env` (git-ignored, read by `envied`; regenerate with `dart run build_runner
build` after any change):

| Var | Required | Purpose |
|---|---|---|
| `API_BASE_URL` | **yes** | Origin of the Eigen server — scheme + host only, **no path, no trailing slash**. Routes carry their own `/api/engine` prefix; the socket is this origin with `ws`/`wss`. |
| `GOOGLE_WEB_CLIENT_ID` | yes | Google Sign-In. |
| `APP_HOST` | optional | This game's public host (a subdomain, or a customer's own domain). One host for everything: invite/replay deep links, the waiting-room QR code, and — when the worker has `site` configured — the terms/privacy tiles and landing page. All of these are hidden when unset. |
| `FIREBASE_VAPID_KEY` | optional | FCM Web Push (web only). |

## 20. Firebase setup (once per deployment)

Firebase is mandatory — the app will not compile without `firebase_options.dart`,
even for local development.

1. **Create the project** at console.firebase.google.com with Analytics enabled.
2. `npm i -g firebase-tools && firebase login`, then
   `dart pub global activate flutterfire_cli`, then **`flutterfire configure`** —
   it registers the Android and iOS apps for you; you do not add them by hand.
3. **Add SHA fingerprints** to the Android app — `flutterfire` does *not* do this,
   and Google Sign-In validates the calling app's certificate at runtime:
   - **Now:** the debug key, so Sign-In works in dev builds.
     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore \
       -alias androiddebugkey -storepass android -keypass android
     ```
   - **After the first Play upload:** the **Play App Signing** certificate
     (Play Console → Release → Setup → App signing). Play re-signs your bundle
     with *their* key, so the app on users' devices is not signed with yours —
     **omitting this is why Sign-In "works in dev and fails in production."**
4. Enable **Crashlytics** (Build → Crashlytics → Get started) and verify **Cloud
   Messaging** is on.
5. **iOS push:** create an APNs `.p8` key at developer.apple.com (Keys → Apple
   Push Notifications service), note the Key ID and Team ID, and upload it under
   Project Settings → Cloud Messaging → Apple app configuration. In Xcode, add the
   **Push Notifications** and **Background Modes → Remote notifications**
   capabilities to the Runner target.
6. **Server-side push credentials:** Project Settings → Service Accounts →
   Generate new private key. The server needs only `client_email` and
   `private_key` from that JSON — set them as Worker secrets and **delete the
   downloaded file**; it grants full Firebase Admin access.

These four generated files are **gitignored and must never be committed** — they
are instance-specific:

| File | Platform |
|---|---|
| `lib/firebase_options.dart` | Dart, all platforms |
| `android/app/google-services.json` | Android native |
| `ios/Runner/GoogleService-Info.plist` | iOS native |
| `firebase.json` | FlutterFire CLI metadata — **not** needed in CI |

Because they're gitignored, CI must reconstruct them (§23).

## 21. Deep links & domain configuration

The **server** hosts the verification files: it generates
`/.well-known/assetlinks.json` (Android) and `apple-app-site-association` (iOS)
from its `deepLink` config, and serves the `/join/{shortCode}` landing page. The
**client** must declare the same host so an installed app intercepts the link.

The app owns **two path prefixes** on this host: `/join/{code}` (invite/share
links) and `/game/{id}` (replay links, and a push notification's deep link).
Everything else the worker serves on the host — `/`, `/terms`, `/privacy`,
`/delete-account` — is deliberately *not* claimed, so it opens in the browser.

`APP_HOST` is therefore declared in **three places that must stay in sync**,
because the OS verifies domain ownership at install time from a value compiled
into the binary:

1. **`.env`** — `APP_HOST=mygame.example.com`, then regenerate envied.
2. **`android/app/src/main/AndroidManifest.xml`** — `android:host` **and a
   `android:pathPrefix` for each of `/join` and `/game`** in the App Links
   `<intent-filter>`. Android fetches `https://<host>/.well-known/assetlinks.json`
   at install; a mismatch silently falls back to the browser.

   The path prefixes are not optional. `assetlinks.json` declares
   `handle_all_urls`, so the *host* is verified as a whole and the
   `<intent-filter>` is the only thing that decides which paths the app claims.
   Without the prefixes the app claims **every** path on the host — including the
   server's `/terms`, `/privacy` and `/delete-account` pages — and the OS hands
   them to a router that has no such route. iOS needs no separate step: the
   server's AASA already scopes Universal Links to `paths: ["/join/*", "/game/*"]`.
3. **`ios/Runner/Runner.entitlements`** — `applinks:mygame.example.com`. **The
   entitlements file alone is not enough**: open Xcode → Runner target → Signing
   & Capabilities and confirm Associated Domains lists it; if stale, remove and
   re-add.

Plus the server's `deepLink` block, which must carry the **release** signing
cert's SHA-256 — not the upload key's, and not the debug key's.

**Android and iOS changes require a new app release** (the host is baked in);
server changes take effect on deploy. Coordinate them.

Verify before submitting: the [Google Digital Asset Links validator] for Android
and an AASA validator for iOS. The usual failures are a fingerprint that doesn't
match the signing keystore, an iOS Team ID mismatch, or the verification file
being served through a redirect.

**Legal pages live on `APP_HOST` — there is no separate legal host.** They used
to need a different domain: App Links covered the whole of `APP_HOST`, so a
`/terms` URL built on it was intercepted and handed to a router with no such
route. Two things removed that constraint — the server's `site` config serves
`/terms`, `/privacy` and `/delete-account` on the game's own host, and the
intent-filter above claims only the `/join` and `/game` prefixes. Legal URLs
therefore fall outside the claimed paths and open in the browser.

**The path prefixes are what make this safe.** An app shipped without them
intercepts its own legal links, and because the host is compiled into the binary,
fixing that needs a new release. If you would rather host legal pages on a
separate domain — for example one canonical policy shared across several games —
just point the app's terms/privacy links there instead; nothing in the engine
requires them to be on `APP_HOST`.

[Google Digital Asset Links validator]: https://developers.google.com/digital-asset-links/tools/generator

## 22. Branding assets

All app-owned — the engine ships no branding, because it has no app to ship.
Author the marks in any vector tool and export the PNG sources; every
platform-specific size is generated.

### App icon

Two 1024 × 1024 PNGs in `assets/icon/` — build-time inputs, so they are *not*
declared under `flutter: assets:`:

| File | Notes |
|---|---|
| `icon.png` | Full square icon, artwork edge-to-edge, opaque. Used for iOS, macOS, web and the legacy Android icon. iOS rejects alpha — set `remove_alpha_ios: true` if the source has any. |
| `icon_foreground.png` | Adaptive-icon foreground: the mark alone on **transparent**, inside the inner ~66%. Android masks it to a circle/squircle and parallaxes it, so anything near the edge is cropped. Also reused as the splash image. |

`dart run flutter_launcher_icons` writes the Android mipmaps + adaptive XML, the
iOS/macOS appiconsets, and the web favicon/icons plus the `icons` array in
`manifest.json`. It never touches `web/index.html`, and it does **not** generate
the notification icon (§15).

### Splash

`flutter_native_splash:` is a **top-level** pubspec key, not nested under
`flutter:`. The reference app reuses `icon_foreground.png` as the splash image so
the splash mark and the home-screen icon are the same file. Regenerate with
`dart run flutter_native_splash:create` after any config or asset change.

Two things to know:

- **On Android 12+ the `image:` key is ignored entirely** — the platform builds
  the splash from the adaptive launcher icon, so the `android_12:` block only
  sets colours. And `-v31` is a *minimum*-version qualifier: that block covers
  API 31 and everything after, not just Android 12.
- **Colours can't read Dart.** `color` / `color_dark` must be kept in sync by hand
  with the theme's surface colours derived from `Branding.seedColor`; a seed
  change means editing them and regenerating.

For a splash mark that differs from the launcher icon, add
`assets/splash/logo.png` (+ `logo_dark.png`) at 1152 × 1152 with artwork inside
the inner 640 px — the outer ring is cropped by Android 12's circular mask.

### Web

A fresh Flutter app ships template values that fail silently: `<title>` is the
project name, the description is "A new Flutter project.", and `manifest.json`
carries Flutter's default `#0175C2`. Replace all of them.

Flutter's web template also has **no Open Graph tags**, so a pasted link renders
as a bare URL. Add `og:*` and `twitter:*` to `<head>`, with `og:image` an
**absolute** URL at 1200 × 630 (`web/og-image.png`) — a relative `og:image` is the
usual reason a preview renders blank, since scrapers don't resolve them. Keep text
centred; some clients crop to a square. Verify with the Facebook Sharing Debugger
after deploying, and re-scrape after changes — both it and Slack cache hard.

*(This is the app's own branding. The **server** renders the per-game share card
at `/join/{code}` from the D1 summary — a different surface.)*

### Reusing these assets on the game's website

The game Worker's `site` config serves a landing page, legal pages and a web
manifest on the game's own host, and it needs exactly the files this section
already produces — **no second icon set, and no extra artwork**. The engine's
default paths are the names `flutter_launcher_icons` emits, so the whole step is
copying `web/` output into the Worker's `public/`:

| This app generates | Copy to the Worker's `public/` | Used for |
|---|---|---|
| `web/favicon.png` | `favicon.png` | Browser tab |
| `web/icons/Icon-192.png` | `icons/Icon-192.png` | Manifest, apple-touch-icon |
| `web/icons/Icon-512.png` | `icons/Icon-512.png` | Manifest |
| `web/icons/Icon-maskable-192.png` | `icons/Icon-maskable-192.png` | Manifest (maskable) |
| `web/icons/Icon-maskable-512.png` | `icons/Icon-maskable-512.png` | Manifest (maskable) |
| `web/og-image.png` | `og-image.png` | Landing-page share card |

All of them derive from the same `assets/icon/icon.png`, except `og-image.png`,
which is the one hand-made 1200 × 630 image this section already asks for. If
you host the Worker on a different origin, the `og:image` it emits is absolute
and built from the request origin, so nothing needs rewriting.

### Checklist

- [ ] `assets/icon/icon.png` + `icon_foreground.png` at 1024 × 1024, foreground
      inside the inner ~66%
- [ ] `flutter_launcher_icons:` adaptive background matches the brand → regenerate
- [ ] `flutter_native_splash:` colours match the theme → regenerate
- [ ] `ic_notification.xml` replaced with this app's monochrome silhouette
- [ ] `web/index.html`: real title + description + OG/Twitter tags, absolute
      `og:image`; `web/og-image.png` at 1200 × 630
- [ ] `web/manifest.json`: real `name`, `short_name`, `description`,
      `background_color` / `theme_color`
- [ ] `web/` icons + `og-image.png` copied into the game Worker's `public/`
- [ ] App Links `<intent-filter>` carries an `android:pathPrefix` for both
      `/join` and `/game` (§21)

## 23. Android release hardening

Two independent mechanisms; enable both.

**R8** (`isMinifyEnabled` + `isShrinkResources` in `android/app/build.gradle.kts`)
shrinks and obfuscates the Java/Kotlin layer. Only libraries that don't ship
their own consumer rules need entries in `proguard-rules.pro` — the Flutter
engine, Play Core (`in_app_update`/`in_app_review`), `google_sign_in`, and
`image_cropper` all bring their own, so the file stays nearly empty by design.
Adding redundant `-keep` rules there is how it rots.

**Dart obfuscation** is a Flutter tool flag, not a Gradle setting — it belongs in
the CI build command:

```bash
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/debug-info/android/
```

Symbol upload splits accordingly: the **R8/ProGuard mapping** is uploaded
automatically by the `firebase-crashlytics-gradle` plugin during the build (as
long as `google-services.json` is present), while **Dart deobfuscation symbols**
are a separate artifact — CI uploads `build/debug-info/` as a workflow artifact.
Without them a release stack trace is unreadable, so keep the retention long
enough to outlive a release.

## 24. CI

Three workflows across the two repos, all Flutter-side:

**`eigen-flutter/.github/workflows/flutter.yml`** — analyze + test the framework
in isolation, so `main` stays green for dependent apps. Needs no secrets: the
framework reads no `Env`/Firebase config itself (apps inject it). The sequence is
`pub get` → format check → `build_runner build` → `dart fix --apply` →
**`git diff --exit-code`** → analyze → test. That diff check is the load-bearing
step — it fails the build if generated code or applied fixes weren't committed.

**`strategy/.github/workflows/android.yml`** — the app pipeline, in three jobs:

- **test** — checks out *both* repos as siblings (the engine via an
  `ENGINE_DEPLOY_KEY` SSH deploy key, since it's private), runs `build_runner` in
  the **engine first** so its generated code exists, writes `.env` from secrets,
  decodes `firebase_options.dart`, then format/analyze/test.
- **build** (main pushes only) — decodes `google-services.json` and the keystore,
  writes `android/key.properties`, builds a signed obfuscated AAB with
  `--build-number=${{ github.run_number }}`, and uploads the AAB and the debug
  symbols as artifacts.
- **deploy** — downloads the AAB and runs `bundle exec fastlane android internal`.

The **path dependency is the reason for the two-repo checkout**: `eigen_flutter`
is consumed by path in local *and* CI until it is published, so CI has to
reproduce the sibling layout that local development uses.

Required GitHub Actions secrets:

| Secret | Used for |
|---|---|
| `ENGINE_DEPLOY_KEY` | SSH deploy key for the private engine repo |
| `API_BASE_URL`, `GOOGLE_WEB_CLIENT_ID`, `APP_HOST` | written into `.env` |
| `FIREBASE_OPTIONS_DART_BASE64` | `lib/firebase_options.dart` (needed in **test** too, or analyze can't resolve the import) |
| `GOOGLE_SERVICES_JSON_BASE64` | `android/app/google-services.json` (build only) |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | iOS equivalent, when iOS CI is added |
| `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` | signing |
| `GOOGLE_PLAY_JSON_KEY` | fastlane `upload_to_play_store` |

Encode with `base64 -i <file> | pbcopy`. `firebase.json` is **not** a CI secret —
it is only used by the `flutterfire` CLI to target the right project on the next
`configure` run, and is never read by a build.

## 25. Compatibility & versioning

Once an app ships, client and server **stop moving together**: a shipped binary
keeps calling a newer backend for weeks, and a daily-timed game can outlive
several releases. Every change must answer *"what does an old client, and an
in-flight game started under the old rules, do when they meet the new code?"*

Three independent version axes:

| Axis | Granularity | Where it lives |
|---|---|---|
| **Package version** | per release | `pubspec.yaml`, git tag |
| **Game schema version** | per game-type revision | `schema_version` on the game row — selects the `GameRules` unit on both sides |
| **Cache schema version** | per persisted model | each provider's `destroyKey` |

### Game schema — version the type, don't mutate games

A breaking rules or payload change never mutates existing games. Each game is
**stamped with the schema version it was created under**, honoured for its whole
life. Neither side branches — each ships another unit under another key.

Client gating: the frame provider looks the game's version up in
`GameModule.versions` and raises `UnsupportedGameSchemaException` rather than
mis-parsing with old code. The **join is gated too**, server-side, so an
unsupported game is refused before a seat is created — not only when the screen
later fails to render. The lobby additionally disables the Join button as
immediate feedback.

**Retiring an old unit splits into two lifetimes, and this is the part that
surprises people:**

- The **write path** (anything that advances state — TS `applyAction`,
  `applyLifecycle`) can go once active games at that version have drained.
- The **read/render path** (TS `computeObservation`, Dart `parseObservation` +
  rendering) must survive **as long as you want to replay games created under
  that schema** — which is *not* bounded by draining. Replay re-projects historic
  transitions at the game's own version.

**Draining gates the write path; replay gates the read path, and replay outlives
draining.**

### Wire compatibility — closed enums, not tolerant decode

An `unknown` enum sentinel would let an unrecognised value degrade gracefully.
**That is deliberately not done here.** Generated enums parse strictly, so an
unknown value throws and `test/shared/api_contract_test.dart` pins the sets.

The trade: graceful degradation on the wire buys silence, and silence is exactly
wrong when the two sides are two repos with one generated seam between them. With
closed enums, adding a value server-side breaks the client **build** — loudly, in
CI, before release — instead of producing a screen that renders nothing at
runtime. That makes adding a wire enum member a coordinated, schema-version-bumped
change, which it always was in truth.

Within a version, additive change is still fine: new fields must be nullable or
`@Default(...)`, never `required`. Changing a field's type or meaning, or removing
it, is breaking → new unit.

### Cache compatibility

A cached-row decode failure must be a **cache miss** (drop, refetch), never a
crash — that is the safety net when a persisted row predates a `destroyKey` bump.
`SharedPreferences` reads must default safely; if a key's value shape changes,
write under a **new key** rather than reinterpreting the old one.

### "I want to change the game" — the checklist

- Alters the observation/action/config shape, or makes in-flight games
  inconsistent? → **breaking**: new `GameRules` unit on both sides + fixtures;
  drain before retiring the write path.
- Purely additive (a new optional field)? → nullable / `@Default`, **no bump**.
- Server-only rule logic, same shapes? → change `applyAction` only, **no bump**.
- New wire enum value? → **breaking**; bump and ship both sides together.
- Persisted model's shape changed? → bump **that provider's** `destroyKey`.

## 26. Store release

Store packaging is app-owned. The reference lives in the `strategy` app.

- **`fastlane/`** — a `Fastfile` with `android internal` and `android production`
  lanes (`upload_to_play_store` with the built AAB), an `Appfile` with the
  `package_name`, and a `Gemfile` pinning the fastlane gem.
- **Per-app setup** — create an upload keystore and add the four signing secrets;
  create a Google Play service account with the *Release* permission and add its
  JSON as `GOOGLE_PLAY_JSON_KEY`; set `applicationId` / bundle id as the app's own
  store identity. **The first upload must be done by hand in the Play Console** to
  create the listing; everything after flows through fastlane.
- iOS submission is **not wired** — add an `ios` lane when targeting iOS.

**The lanes upload the binary only.** Both pass `skip_upload_metadata`,
`skip_upload_images`, and `skip_upload_screenshots`, so the listing (icon,
feature graphic, screenshots, description) is maintained by hand in the Console
and CI will never overwrite it. That is deliberate — store copy changes on a
different cadence than code. To flip it, drop assets into
`fastlane/metadata/android/en-US/images/` and remove the matching `skip_upload_*`
flags; from then on the repo is the source of truth and fastlane overwrites
Console edits.

Play's asset requirements (512 × 512 icon, 1024 × 500 feature graphic, ≥ 2 phone
screenshots) tighten periodically — confirm against Google's current spec before
a first submission rather than trusting a copy of it. There is no screenshot
automation; capture from an emulator at a qualifying resolution with
`adb exec-out screencap -p > shot.png`, using a seeded account with realistic
games in progress.

---

## 27. The client/server boundary

What the **client** owns: rendering, animation, optimistic preview
(`previewAction`), the frame-stream/reconnect state machine, all shell concerns
(navigation, splash, offline UX, persistence cache, push registration, analytics,
platform integration), and the create/lobby UX.

What the **server** owns (client never reimplements): the rules, timing and
expiry, seat authority, ratings, history, identity resolution, and every write's
policy. The client proposes; the server decides.

The two rules twins (Dart preview, TS authority) are kept honest by shared JSON
fixtures run on both sides — a drift fails a test in both languages. When in
doubt about behaviour, the server's TS rules are the truth; the Dart twin exists
only to hide latency and render.
