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

Two jobs. The framework: `pub get` → format check → framework codegen →
`dart fix --apply` → **`git diff --exit-code`** → analyze → dartdoc dry run →
test. The example: resolve, regenerate payloads from `game-contract.json`,
format, analyze, test.

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

Its payload types and `fixtures/v1/rps.json` are generated from the server
example's deterministic `game-contract.json`. Regenerate with
`dart run eigen_flutter:generate_payloads`; never hand-edit generated payloads
or fixture copies.

It is also a **published artifact**. pub.dev renders `example/` on the package
page, so it is documentation with a compiler attached — which is the point, but
it means a breaking change to the barrel breaks it, and that is a signal worth
listening to rather than papering over.

## The generated API client

`eigen_api` is **not in this repository.** It is generated from `openapi.json`
in the engine repo (`eigen-server/clients/dart`), published to pub.dev at the
engine's version, and consumed here as an ordinary dependency:
`eigen_api: ^0.1.0`.

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

Generated engine API enums include `unknownDefaultOpenApi` for read-side forward
compatibility. Exhaustive switches must handle it, normally by presenting an
update-required state. It must never be serialized back to the server.

## Game contract and twin fixtures

A game's Worker emits schemas and validated fixtures into one deterministic
`game-contract.json`. The Flutter generator emits payload classes, typed rules
bases, and fixture copies from that artifact. In separate repositories, pin the
artifact by checksum and run the generator in `--check` mode in CI.

## Describing your change

`CHANGELOG.md` is maintained with [`cider`](https://pub.dev/packages/cider),
Keep-a-Changelog style. Install it once:

```bash
dart pub global activate cider
```

**In the PR that makes the change**, add the line a user will read:

```bash
cider log added "Spectator mode on the game screen."
cider log fixed "Avatar cache not invalidated after upload."
```

Each call appends a bullet under `## [Unreleased]`. The types are `added`,
`changed`, `deprecated`, `removed`, `fixed` and `security`. Commit the
`CHANGELOG.md` edit with your code.

Do this *as you work*, not at release time. It is the same discipline as the
engine repo's `pnpm changeset`: whoever made the change is the only person who
reliably knows what it means for a user, and they know it now.

A change with no user-visible effect needs no entry.

> The `cider:` block in `pubspec.yaml` supplies the tag and diff link templates,
> so `cider release` decorates each section with links to the GitHub release and
> the compare view. Nothing else reads it.

## Releasing to pub.dev

After the first publication, releases are tag-driven and `cider` does the
bookkeeping:

```bash
cider bump minor      # or: patch · breaking
cider release         # [Unreleased] -> a dated, linked section
git commit -am "Release $(cider version)"
git tag "v$(cider version)"
git push --follow-tags
```

`cider bump` edits `version:` in `pubspec.yaml`; `cider release` moves everything
under `## [Unreleased]` into a dated section for that version. The tag must match
the pubspec — the release workflow re-checks it and refuses to publish a
mismatch, because a tag can point at any commit.

> **Use `cider bump breaking`, not `major`, while this package is pre-1.0.**
> Under pub's semantics a `0.x` release conveys breakage in the *minor*
> position, so `breaking` takes `0.1.0` → `0.2.0`, which is what a consumer's
> `^0.1.0` constraint actually protects against. `cider bump major` would jump
> to `1.0.0` and claim a stability guarantee you have not made yet.

Authentication is **OIDC**, not a stored token: configure *Automated publishing*
on the pub.dev package page (Admin → Automated publishing) with repository
`eigeninteractive/eigen-flutter` and tag pattern `v{{version}}`, and pub.dev
trusts the workflow's short-lived GitHub identity. There is no pub credential in
GitHub secrets.

The first version is the one exception: pub.dev requires a new package to be
published interactively with `dart pub publish`. Publish it from a clean,
fully validated checkout, then transfer it to the verified publisher and
enable the GitHub repository/tag pattern above. Automated publishing handles
subsequent versions.

One package. `eigen_api` is released by the engine repo, so there is no lockstep
to coordinate and no publish order to get right — bumping the `eigen_api`
constraint here is an ordinary dependency change with an ordinary changelog line.

### Before you tag

Run the two publication-specific checks locally:

```bash
dart doc --dry-run .
dart pub publish --dry-run
```

`dartdoc_options.yaml` limits the hosted reference to the supported
`eigen_flutter` and `eigen_flutter.testing` libraries and treats unresolved
references as errors. pub.dev generates and hosts the HTML automatically; do
not commit `doc/api` or copy it into `eigen-web`.

After publication, verify the version's documentation status in the pub.dev
Versions tab. The Eigen documentation links to
`https://pub.dev/documentation/eigen_flutter/latest/`, while pub.dev retains a
separate reference for every older package version.

`pubspec_overrides.yaml` is gitignored, so it cannot reach the published
manifest — but if you added a `dependency_overrides:` block to `pubspec.yaml`
itself while working on both halves, the release would ship a package whose
`eigen_api` constraint has never actually been resolved. The workflow fails the
build on that rather than publishing it; a pub.dev version cannot be
unpublished, only retracted.

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
