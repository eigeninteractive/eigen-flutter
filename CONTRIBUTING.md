# Contributing to eigen-flutter

This repository contains the Flutter client framework, app shell, transport,
and Dart half of the game contract.

Game-implementor documentation lives at
[eigeninteractive.com](https://eigeninteractive.com). This guide is for people
changing framework code. Publishing, registry configuration, release tags, and
failure recovery live in [MAINTAINERS.md](MAINTAINERS.md).

## Getting set up

```bash
flutter pub get
dart run build_runner build
flutter analyze
flutter test
```

The example is a separate package with its own dependency resolution:

```bash
cd example
flutter pub get
flutter analyze
flutter test
```

No Firebase project or `.env` is needed. Applications inject runtime values
through `EngineConfig`.

> [!WARNING]
> Never commit a real game's `.env`, Firebase client files, keystores, or `.p8`
> keys to this engine repository. Firebase client identifiers are public, but
> they belong in the consuming game repository. The checked-in RPS example
> keeps only throwing placeholders so analysis and browser compilation work
> without an engine-owned Firebase project.

## Branching

Work on a branch and open a pull request. `main` is protected and release tags
must point at commits already on it.

## The CI gate

The framework job resolves dependencies, checks formatting, regenerates source,
applies Dart fixes, verifies a clean diff, analyzes, validates Dartdoc, and
tests. The example job resolves its own package, regenerates game payloads from
`game-contract.json`, formats, analyzes, and tests.

The clean-diff check is intentional: generated Dart source is committed, so CI
must prove the checked-in output matches its inputs.

Formatting runs against tracked handwritten Dart files rather than `.` because
`dart format` has no exclude flag and generated `*.g.dart`/`*.freezed.dart`
output should not be mechanically reformatted.

## The example

`example/` is Rock–Paper–Scissors: a complete game and the package's
consumer-style integration test. Keep it using the public barrel and a
hand-built `GameContentContext`; do not give it privileged access to internal
libraries.

Its payload types and fixture copies are generated from the server example's
deterministic `game-contract.json`:

```bash
cd example
dart run eigen_flutter:generate_payloads
```

Never hand-edit generated payloads or fixture copies. The example is also
included on pub.dev, so treat its code as executable API documentation.

## Working with `eigen_api`

The generated REST client is owned by
`eigen-server/clients/dart` and published separately as `eigen_api`. This
package consumes it as a normal versioned dependency.

For cross-repository development, clone `eigen-server` as a sibling and create
a gitignored `pubspec_overrides.yaml`:

```yaml
dependency_overrides:
  eigen_api:
    path: ../eigen-server/clients/dart
```

The example needs its own override with the corresponding relative path because
it is a separate package root. Never place the override in `pubspec.yaml`; the
declared registry constraint must be tested before publication.

Generated response enums include `unknownDefaultOpenApi`. Exhaustive switches
must handle it, normally by presenting an update-required state. It is a
read-side sentinel and must never be serialized back to the server.

## Game contracts and twin fixtures

A game's Worker emits schemas and validated fixtures into one deterministic
`game-contract.json`. The Flutter generator emits payload classes, typed rules
bases, and fixture copies from that artifact.

In separate repositories, pin the contract artifact by checksum and run the
generator in `--check` mode in CI. A fixture or payload change must land with
the matching TypeScript rules change.

## Describing your change

`CHANGELOG.md` follows Keep a Changelog and is maintained with
[`cider`](https://pub.dev/packages/cider). Install it once:

```bash
dart pub global activate cider
```

In the pull request that introduces a user-visible change, add the line package
consumers should read:

```bash
cider log added "Spectator mode on the game screen."
cider log fixed "Avatar cache not invalidated after upload."
```

Valid categories are `added`, `changed`, `deprecated`, `removed`, `fixed`, and
`security`. Commit the resulting `CHANGELOG.md` edit with the code. A purely
internal change needs no entry.

Do this while making the change, not at release time. The maintainer later
turns the accumulated `Unreleased` section into a version without rewriting
the contributor's intent.

**Use the command; do not hand-write the section.** Every `## [x]` heading needs
a matching `[x]: <url>` reference definition at the bottom of the file, because
that is the only thing that makes the heading parse as a link, and cider finds
its sections by looking for links, not by matching text. A heading without one is
invisible to `cider release`, which then leaves your entry in place, appends an
empty version section, and exits 0. `cider log` writes both halves; typing the
heading yourself writes one. CI checks this, since the failure is otherwise
silent until a release is already open.

Reformatting is expected and fine. cider re-serialises the whole file, so it will
unindent your wrapped list continuations and drop blank lines after headings. It
renders identically. Leave it alone rather than restoring the wrapping, which
only guarantees the next release diff is noisy again.

## Generated code

`*.g.dart` and `*.freezed.dart` are committed. Consumers do not run
`build_runner` on dependencies, and the committed output lets code generation
plus a clean-diff check detect drift.

Publishing falls back to `.gitignore`; no `.pubignore` is needed. Adding an
incomplete `.pubignore` would replace, rather than extend, `.gitignore` and
could accidentally include credentials.

## Documentation changes

Public behavior belongs in the task-first guides in
[`eigen-web`](https://github.com/eigeninteractive/eigen-web), with the
TypeScript and Dart halves on the same page. Public API detail belongs in `///`
comments so pub.dev's Dartdoc reference stays attached to the declaration.

Repository-development instructions belong here. Privileged operational
instructions belong in [MAINTAINERS.md](MAINTAINERS.md).
