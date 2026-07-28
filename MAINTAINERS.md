# Maintaining eigen-flutter

This guide is for people authorized to publish `eigen_flutter`, configure
pub.dev and repository release settings, or recover a failed release.

For local setup, code generation, testing, changelog entries, and pull-request
expectations, start with [CONTRIBUTING.md](CONTRIBUTING.md).

## Release relationship

`eigen_flutter` and `eigen_api` have independent release cycles.
`eigen_api` belongs to `eigen-server` because it implements that repository's
wire contract; this package consumes it through the constraint in
`pubspec.yaml`.

Routine releases have no lockstep requirement. The bootstrap exception is the
first publication: `eigen_api` must already resolve from pub.dev before
`eigen_flutter` can validate and publish without a local override.

When a later engine release is incompatible with the current `eigen_api`
constraint, update the constraint as an ordinary dependency change and include
the user-visible consequence in `CHANGELOG.md`.

## Required configuration

After the first publication, configure `eigen_flutter` under
**pub.dev → Admin → Automated publishing**:

```text
Repository:  eigeninteractive/eigen-flutter
Tag pattern: v{{version}}
```

`.github/workflows/release.yml` uses GitHub OIDC, so no long-lived pub.dev
credential belongs in repository secrets. The workflow requires
`permissions.id-token: write`.

## First publication

First publication is interactive because pub.dev cannot configure automated
publishing for a package that does not exist yet.

1. Publish `eigen_api` from `eigen-server/clients/dart`.
2. Use a clean eigen-flutter checkout with no `dependency_overrides` in
   `pubspec.yaml`.
3. Run the complete framework and example CI gates.
4. Run:

   ```bash
   dart doc --dry-run .
   dart pub publish --dry-run
   dart pub publish
   ```

5. Transfer the package to the verified Eigen Interactive publisher.
6. Configure automated publishing with the repository and tag pattern above.

Do not push `v0.1.0` after publishing that version interactively. Tag-driven
publication begins with the next version.

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
dart run build_runner build --delete-conflicting-outputs
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

`dartdoc_options.yaml` limits the hosted reference to the supported
`eigen_flutter` and `eigen_flutter.testing` libraries and treats unresolved
references as errors.

pub.dev generates and hosts documentation for every published version. Do not
commit `doc/api` or copy generated Dartdoc HTML into `eigen-web`. After
publication:

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
