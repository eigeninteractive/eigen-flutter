# Rock–Paper–Scissors

A complete game on the EigenInteractive client, in about 500 lines. It is the
client half
of the RPS example in
[`eigen-server/examples/rps`](https://github.com/eigeninteractive/eigen-server/tree/main/examples/rps),
and the two halves are checked against each other by the shared fixtures in
`fixtures/`.

RPS is small but not easy: both players commit at the same time and neither may
see the other's throw. That makes it the *hardest* case for a client (hidden
information, simultaneous turns, and nothing worth predicting) so what it does
and does not do is worth reading before you write your own.

## What's here

| File | What it is |
|---|---|
| `lib/main.dart` | The whole app: which game, what it's called, where the server is |
| `lib/src/rps_module.dart` | The version registry, the create dialog, the rules page |
| `lib/src/v1/models.dart` | Generated payload types and handwritten helpers, the Dart mirror of the TypeScript schemas |
| `lib/src/v1/rules.dart` | The `GameRules` unit: legality, optimism, and what to render |
| `lib/src/v1/board.dart` | The board |
| `fixtures/v1/rps.json` | Behaviour recorded once, run by both languages |

Everything else a player touches (sign-in, home, lobby, friends, profile,
settings, history, replay, push, deep links) is `eigen_flutter`, and no code
here is involved in any of it.

## The division of labour

The server decides; the client draws and proposes. Concretely, the TypeScript
unit owns `initialState`, `applyAction`, `applyLifecycle`, `computeObservation`
and the payload schemas. This side inherits generated payload parsing, then owns
the legality check behind a greyed-out button, the optimism contract, and the
widgets.

Where the two overlap (legality, `ratingPool`, `botSeatable`) they are
transcriptions of each other, and drifting apart is a bug the fixtures catch.

## Two things RPS teaches that a simpler game would not

**The observation is not the state.** `computeObservation` projects a different
payload per seat, and for RPS it emits two different *shapes*: live play carries
`yourMove` and simply omits the opponent's commit, while replay carries
`commits` for both seats because the match is over. The opponent's throw is not
hidden by the UI; it is not in the bytes. `RpsV1Observation.fromJson` handles
both shapes, and that is the entire cost of hidden information on the client.

**`previewAction` returns null, and that is the right answer.** The engine also
masks the opponent's *pending* status, so after you throw you cannot tell
whether you are waiting or whether you just resolved the round. Predicting
either would be wrong half the time. The board still feels instant, because it
holds the tapped move in widget state and resolves it against the
`ActionSubmitResult` the submit returns: optimism about your own action, which
you can always know, rather than about the resulting position, which here you
cannot.

That same masking is what makes simultaneous play work at all: because a hidden
commit does not change your view, the engine's same-view rule lets both
submissions land in either order.

## Running it

```bash
flutter pub get
flutter test
flutter build web --release --dart-define-from-file=app-config.json
```

Playing it against a real server needs two things this repository deliberately
does not contain: a Firebase project and a deployed worker. Configure Firebase
without copying its Web identifiers by hand:

```bash
dart run eigen_flutter:configure_firebase
```

The command runs FlutterFire for Android and Web, then generates
`web/firebase-config.js` from the same selected Web app. Fill the remaining
public values, including the VAPID key, in `app-config.json` once you have both
services. Required values start empty so an incorrectly configured app fails at
startup with one actionable error.

For an interactive browser run, use the fixed OAuth/Worker origin:

```bash
flutter run -d chrome --web-hostname localhost --web-port 7357 \
  --dart-define-from-file=app-config.json
```

Configure Firebase and the VAPID key first. See the
[web deployment guide](https://eigeninteractive.com/docs/ship-it/deploy-the-web-app)
for Firebase authorized domains, Worker CORS and hosting rules.

Use that same file for an Android release:

```bash
flutter build appbundle --release \
  --dart-define-from-file=app-config.json
```

> **`dependency_overrides` in `pubspec.yaml`** is temporary. `eigen_flutter`
> depends on `eigen_api` by version, but the override that points it at the
> local checkout is honoured only for the *root* package, and here the root is
> this example, so it has to be repeated. Delete the block once `eigen_api` is
> published; an app depending on `eigen_flutter` never needs it.

## The generated contract

The server example emits `game-contract.json` from its four schemas and
validated fixtures. `payloads.dart` and `fixtures/v1/rps.json` are generated
from that artifact, so they are not handwritten mirrors. Separate repositories
exchange the artifact by release/checksum rather than depending on one another's
checkout layout.

Note that a case's `pending` array is written from the server's point of view.
The client normally sees a masked projection of it, which for RPS is at most
your own seat. No case turns on the difference, but your game's might.
