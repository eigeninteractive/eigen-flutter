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

> [!IMPORTANT]
> **Publishing is currently blocked.** pub.dev rejects packages with `path`
> dependencies, and `eigen_flutter` depends on `packages/eigen_api` by path.
> `publish_to: none` in `pubspec.yaml` reflects that.
>
> Resolving it means either publishing `eigen_api` separately and depending on
> it by version, or folding the generated client into `eigen_flutter/lib/src/`.
> The second is the better fit: `eigen_api` is a build artifact, and the
> architecture already forbids apps from depending on it directly — so
> publishing it as a public package would contradict its own contract and make
> every wire change a two-package release.

## Documentation changes

Changing behaviour usually means changing docs, and the docs are in another
repository. Open a matching PR against
[`eigen-web`](https://github.com/eigeninteractive/eigen-web).
