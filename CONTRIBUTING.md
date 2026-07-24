# Contributing to eigen-flutter

This is the Flutter client framework — the app shell, the transport, and the
Dart half of a game's rules contract.

User-facing documentation lives at
**<https://eigeninteractive.com/docs/client/overview>** and is authored in the
[`eigen-web`](https://github.com/eigeninteractive/eigen-web) repository — not
here. This file is for people working *on* the framework.

## Getting set up

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
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

`pub get` → format check → `build_runner build` → `dart fix --apply` →
**`git diff --exit-code`** → analyze → test.

That diff check is the load-bearing step: it fails the build if generated code
or applied fixes were not committed.

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
sharing mechanism.**

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
> `dart pub publish` honours `.gitignore`. Today that means **71 generated files
> exist on disk and zero would be published** — a consumer would install a
> package whose `part 'foo.g.dart';` directives point at files that do not
> exist, and it would not compile.
>
> Consumers never run `build_runner` on a dependency, so a published Dart
> package has to ship its generated code. Fixing this means removing those two
> `.gitignore` lines and committing the generated output, accepting the diff
> noise on every regeneration. It applies to both packages.

## Documentation changes

Changing behaviour usually means changing docs, and the docs are in another
repository. Open a matching PR against
[`eigen-web`](https://github.com/eigeninteractive/eigen-web).
