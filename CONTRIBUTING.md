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
# The generated REST client is a separate package, and the root build does not
# reach into a path dependency. Skip this and every model that parses a
# response fails to compile.
(cd packages/eigen_api && dart pub get && dart run build_runner build)
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

`packages/eigen_api` is **generated** from a vendored snapshot of the engine's
`openapi.json` (`openapi/openapi.json`). `tool/generate_api.sh` deletes and
rewrites it wholesale — never hand-edit it, and never depend on it from an app.

It usually refreshes itself: eigen-server dispatches here when its spec changes,
and `.github/workflows/sync-api.yml` re-vendors the spec, regenerates the
client, and opens a PR.

**If that PR's checks fail, the engine made a breaking wire change.** Generated
enums carry no `unknown` sentinel and parse strictly, so a new member is a
compile error by design. That needs a coordinated schema-version bump across
both repos, not a fix here.

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

### Two packages, one version

`eigen_api` is published too, and the two release **in lockstep** — same version,
always together. `eigen_flutter` declares `eigen_api: ^<same version>`, which is
a real version constraint (pub.dev rejects `path` dependencies), and a
`dependency_overrides` entry points at the local checkout while you work.

That override is honoured **only when `eigen_flutter` is the root package**, so
an app depending on `eigen_flutter` resolves the published `eigen_api` normally.
It also keeps `eigen_api`'s dependency resolution independent, which matters:
its `build_runner` needs a newer `analyzer` than `riverpod_lint` allows, so a
pub workspace — which forces one shared resolution — will not resolve.

Publish order is `eigen_api` first, then `eigen_flutter`.

`eigen_api` being on pub.dev does not make it public API. It is documented as
internal and no app should depend on it directly, the same way Flutter's
federated plugins publish `*_platform_interface` packages nobody imports.

> [!IMPORTANT]
> **Publishing is blocked until generated code is committed.**
>
> `.gitignore` currently excludes `*.g.dart` and `*.freezed.dart`, and
> `dart pub publish` honours `.gitignore`. Today that means **73 generated files
> exist on disk and zero would be published** — a consumer would install a
> package whose `part 'foo.g.dart';` directives point at files that do not
> exist, and it would not compile. The example is included in the tarball, so
> its two generated files are affected too.
>
> Consumers never run `build_runner` on a dependency, so a published Dart
> package has to ship its generated code. Fixing this means removing those two
> `.gitignore` lines and committing the generated output, accepting the diff
> noise on every regeneration. It applies to both packages.

## Documentation changes

Changing behaviour usually means changing docs, and the docs are in another
repository. Open a matching PR against
[`eigen-web`](https://github.com/eigeninteractive/eigen-web).
