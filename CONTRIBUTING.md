# Contributing to eigen-flutter

This is the Flutter client framework — the app shell, the transport, and the
Dart half of a game's rules contract.

User-facing documentation lives at
**<https://eigeninteractive.com/docs/build-a-game/the-contract>** — the docs are
task-first, so the client half of each topic sits on the same page as the server
half rather than in a section of its own. It is authored in the
[`eigen-web`](https://github.com/eigeninteractive/eigen-web) repository — not
here. This file is for people working *on* the framework.

## Getting set up

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

And the example, which is its own package with its own resolution:

```bash
cd example
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # its models are Freezed
flutter analyze && flutter test
```

No Firebase project or `.env` is needed to work on the framework itself: it
reads no runtime config, because apps inject it via `EngineConfig`.

> [!WARNING]
> Never commit `.env`, `lib/firebase_options.dart`, `google-services.json`,
> `GoogleService-Info.plist`, keystores or `.p8` keys. `.gitignore` covers all
> of them — CI writes two of them from secrets in order to analyze, so those
> rules are what stop a local run of the same steps from committing real
> credentials.

## Branching

Work on a branch and open a pull request. `main` is protected and is the only
branch that releases.

## The CI gate

Two jobs. The framework: `pub get` → format check → codegen (both packages) →
`dart fix --apply` → **`git diff --exit-code`** → analyze → test. The example:
resolve, format, codegen, analyze, test.

That diff check is the load-bearing step: it fails the build if generated code
or applied fixes were not committed.

The format check runs against `git ls-files` minus `*.g.dart` and
`*.freezed.dart` rather than against `.`. `dart format` has no exclude flag, and
`build_runner` output does not reliably survive it — so a plain `dart format .`
fails locally on generated files even when every hand-written file is clean.
Listing the files keeps the same command honest locally and in CI, and keeps
working if generated code is ever committed.

## The example

`example/` is Rock–Paper–Scissors: a complete game, and the only place the
framework is exercised the way a real game uses it — through the barrel, with a
`GameContentContext` built by hand. Its `test/board_test.dart` is the worked
answer to "how do I test a game screen", so keep it working.

Its `fixtures/v1/rps.json` is a copy of the server's, and the server runs the
same file against the authoritative TypeScript unit. See the fixture note below:
changing one copy without the other is the failure mode.

Its payload types are **Freezed**, like a real game's, so it has its own
`build_runner` step and its own `build.yaml`. That file deliberately sets no
`field_rename`: this game's wire keys are camelCase, while the framework package
uses `field_rename: snake` for the engine's own snake_case vocabulary. Copying
one into the other is a real way to break a codec, and the example is where that
distinction is demonstrated rather than described.

It is also a **published artifact**. pub.dev renders `example/` on the package
page, so it is documentation with a compiler attached — which is the point, but
it means a breaking change to the barrel breaks it, and that is a signal worth
listening to rather than papering over.

## The generated API client

`eigen_api` is **not in this repository.** It is generated from `openapi.json`
in the engine repo (`eigen-server/clients/dart`), published to pub.dev at the
engine's version, and consumed here as an ordinary dependency:
`eigen_api: ^1.0.0`.

That is a deliberate move away from vendoring the spec and regenerating locally.
The wire contract belongs to the server, so the client that speaks it is
versioned by the server — and a breaking wire change now appears as a reviewable
Dart diff in the engine PR that caused it, instead of arriving here days later
as a failing sync PR. There is no dispatch workflow and no vendored spec.

**To work on both halves at once**, clone `eigen-server` as a sibling and create
a `pubspec_overrides.yaml` — it is gitignored, pub reads it alongside
`pubspec.yaml`, and it keeps the override out of the published manifest:

```yaml
dependency_overrides:
  eigen_api:
    path: ../eigen-server/clients/dart
```

The example needs its own copy (with one more `../`), because
`dependency_overrides` applies only to the root package and the example is its
own root.

**A wire change that fails to compile here is the engine telling you it broke
the wire.** Generated enums carry no `unknown` sentinel and parse strictly, so a
new member is a compile error by design. That needs a coordinated
schema-version bump across both repos, not a fix here.

## Twin fixtures — the coupling CI cannot see

A game's rules exist twice: TypeScript on the server, Dart here. The JSON
fixtures that pin their agreement are **duplicated into both repos with no
sharing mechanism** — for RPS, `example/fixtures/v1/rps.json` here and
`examples/rps/src/rules/fixtures/v1/rps.json` in `eigen-server`.

Editing a fixture in one repo leaves that repo green while the other holds a
stale copy, and nothing fails until the other repo's CI next runs — possibly
days later, on someone else's PR. **A rules change is a two-repo change**, and
the fixture edit is the part that must land in both.

## Releasing to pub.dev

Tag-driven:

```bash
# bump `version:` in pubspec.yaml, update CHANGELOG.md, commit
git tag v0.2.0
git push --follow-tags
```

Authentication is **OIDC**, not a stored token: configure *Automated publishing*
on the pub.dev package page (Admin → Automated publishing) with repository
`eigeninteractive/eigen-flutter` and tag pattern `v{{version}}`, and pub.dev
trusts the workflow's short-lived GitHub identity. There is no pub credential in
GitHub secrets.

One package. `eigen_api` is released by the engine repo, so there is no lockstep
to coordinate and no publish order to get right.

### Generated code is committed

`*.g.dart` and `*.freezed.dart` are **not** gitignored here — they are committed,
for two reasons. A published Dart package must ship its generated code, because
a consumer never runs `build_runner` on a dependency; and committing it makes
`build_runner` + `git diff` the drift guard that proves the checked-in copy is
current (the "no pending fixes" step above).

Because the generated sources are tracked, publishing needs no `.pubignore`:
`dart pub publish` falls back to `.gitignore`, which already excludes build
output and the credential set while keeping the generated code. That is the
safer arrangement — a `.pubignore` *replaces* `.gitignore` rather than adding to
it, so an incomplete one silently re-includes `.env`, keystores and
`firebase_options.dart`.

## Documentation changes

Changing behaviour usually means changing docs, and the docs are in another
repository. Open a matching PR against
[`eigen-web`](https://github.com/eigeninteractive/eigen-web).
