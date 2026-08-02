# Maintaining eigen-flutter

This guide is for people authorized to publish `eigen_flutter`, configure
pub.dev and repository release settings, or recover a failed release.

For local setup, code generation, testing, changelog entries, and pull-request
expectations, start with [CONTRIBUTING.md](CONTRIBUTING.md).

Temporary compatibility code that cannot yet be removed because of upstream
packages is tracked in [`eigen-server/docs/blockers.md`][blockers] — one
cross-repository list, because the Flutter and engine workarounds get reviewed
at the same moments and two lists meant neither was re-checked.

[blockers]: https://github.com/eigeninteractive/eigen-server/blob/main/docs/blockers.md

## Release relationship

`eigen_flutter` and `eigen_api` have independent release cycles.
`eigen_api` belongs to `eigen-server` because it implements that repository's
wire contract; this package consumes it through the constraint in
`pubspec.yaml`.

Releases have no lockstep requirement. When an engine release is incompatible
with the current `eigen_api` constraint, update the constraint as an ordinary
dependency change and include the user-visible consequence in `CHANGELOG.md`.

## Registry configuration

`eigen_flutter` is published by the verified `eigeninteractive.com` publisher,
with automated publishing configured under **pub.dev → Admin → Automated
publishing**:

```text
Repository:  eigeninteractive/eigen-flutter
Tag pattern: v{{version}}
```

Recorded here because it is invisible from the repository and a wrong value
fails only at publish time. It is the pub.dev side of the contract
`.github/workflows/release.yml` relies on: pub.dev trusts a GitHub OIDC token
only when the token's ref is a tag matching that pattern, which is why the
workflow is tag-triggered rather than push-triggered. No long-lived pub.dev
credential exists in repository secrets — the OIDC identity is the
authentication, and the workflow needs `permissions.id-token: write` to obtain
it.

## Preparing a routine release

Contributors maintain the `Unreleased` changelog section with `cider log`.
Review those entries and choose the package bump:

```bash
cider bump patch       # compatible correction or addition
cider bump breaking    # breaking change while pre-1.0
cider release          # date and link the Unreleased section
```

While pre-1.0, use `cider bump breaking`, not `major`, for a breaking release.
It advances `0.1.x` to `0.2.0`, which matches the protection provided by a
consumer's `^0.1.0` constraint. `major` would jump to `1.0.0` and claim a
stability milestone.

Review the resulting `pubspec.yaml` and `CHANGELOG.md`, then run:

```bash
flutter pub get
dart run build_runner build
dart format --output=none --set-exit-if-changed \
  $(git ls-files '*.dart' ':!:**/*.g.dart' ':!:**/*.freezed.dart')
flutter analyze
flutter test
(cd example && flutter pub get && flutter analyze && flutter test)
dart doc --dry-run .
dart pub publish --dry-run
```

The release must resolve the published `eigen_api`, not a sibling checkout.
Remove any local `pubspec_overrides.yaml` before this validation even though it
is gitignored.

Commit the version and changelog:

```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "Release $(cider version)"
git push origin HEAD
```

Merge the release commit to `main` before tagging it.

## Publishing

Create a tag matching the version in `pubspec.yaml` and push that exact tag:

```bash
git tag "v$(cider version)"
git push origin "v$(cider version)"
```

`.github/workflows/release.yml` checks out the tag, reruns generation, analysis,
Dartdoc, tests, and `dart pub publish --dry-run`, verifies the tag/version
match, and publishes using pub.dev OIDC.

Generated source remains committed and ships in the package. Consumers never
need this repository's builders to use `eigen_flutter`.

## Dart API documentation

**pub.dev builds and hosts Dartdoc for every published version.** Nothing here
runs `dart doc` for publication, and no generated HTML is committed or copied
into `eigen-web`. This is deliberate, and the opposite of how the TypeScript
side works — eigen-web vendors generated references from `eigen-server` because
npm hosts nothing comparable. Dart needs no such machinery:

- pub.dev's build is **versioned**. `/documentation/eigen_flutter/0.1.0/` stays
  reachable forever, so a consumer on an old version reads the API they
  actually have. A copy in eigen-web would only ever describe `latest`.
- It is wired into pub.dev search, the package score, and source links back to
  the tagged commit. A vendored copy has none of that.
- It cannot drift. There is no step to forget, and no third place for the
  Dart API to be described.

eigen-web therefore **links** to pub.dev rather than rendering the Dart API,
and `eigen_api` is documented the same way from `eigen-server`.

What this repository owns is the *input* to that build. `dartdoc_options.yaml`
limits the hosted reference to the supported `eigen_flutter` and
`eigen_flutter.testing` libraries and treats unresolved references as errors.
`checks.yml` runs `dart doc --dry-run .`, and `release.yml` calls that same
gate against the tag, so a documentation error fails the release rather than
surfacing later as a broken build on pub.dev. Public API detail belongs in
`///` comments for this reason.

After publication:

1. Check the version's documentation status on pub.dev.
2. Open `https://pub.dev/documentation/eigen_flutter/latest/`.
3. Verify both supported library pages and their source links.
4. Verify eigen-web's Dart reference link reaches the new latest version.

## Failure recovery

- **A check fails before publication:** fix the source and create a new tag on
  the corrected commit. Never move a published tag silently.
- **The workflow fails before `dart pub publish`:** delete the unpublished bad
  tag, correct the release commit, and create the same version tag again.
- **The version was published:** never reuse it. Correct the problem, add a
  changelog entry, and publish a new patch or breaking version as appropriate.
- **A harmful version shipped:** use pub.dev retraction, communicate the
  affected range, and publish the replacement. Published versions cannot be
  overwritten.
- **Dartdoc failed on pub.dev despite the dry run:** inspect the hosted build
  log, correct the documentation source, and publish a new version.

Record exceptional recovery steps in the release notes or a repository issue
so the package, tag, and source history remain reconstructable.
