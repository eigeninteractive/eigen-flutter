# Maintaining eigen-flutter

This guide is for people authorized to publish `eigen_flutter`, configure
pub.dev and repository release settings, or recover a failed release.

For local setup, code generation, testing, changelog entries, and pull-request
expectations, start with [CONTRIBUTING.md](CONTRIBUTING.md).

Temporary compatibility code that cannot yet be removed because of upstream
packages is tracked in [`eigen-server/docs/blockers.md`][blockers]: one
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
credential exists in repository secrets; the OIDC identity is the
authentication, and the workflow needs `permissions.id-token: write` to obtain
it.

The release workflows do need the **eigen-release** GitHub App, which is
installed across the organisation. Two values must resolve in this repository,
either set here or inherited from the organisation:

| | |
|---|---|
| `vars.RELEASE_APP_CLIENT_ID` | the App's client ID (`Iv23…`), not the deprecated App ID |
| `secrets.RELEASE_APP_PRIVATE_KEY` | the App's PEM private key |

Organisation level is preferable: `eigen-server` needs the same pair, and one
copy means one place to rotate the key.

## Releasing

Releasing is one decision, which bump, and one review. There are no local
commands, and nothing to remember to run afterwards.

1. **Dispatch the bump.** Actions → **Version** → Run workflow, or:

   ```bash
   gh workflow run version.yml -f bump=minor
   ```

   `version.yml` runs `cider bump` and `cider release` on a fresh `main` and
   opens a **Release vX.Y.Z** pull request. Because each run starts from
   `main`, dispatching twice cannot compound bumps.

2. **Review and merge it.** The pull request is the release decision, and the
   last reversible moment: pub.dev versions cannot be unpublished, only
   retracted. Read the dated `CHANGELOG.md` section as a consumer would, and
   confirm the bump matches what actually changed.

3. **Everything after that is automatic.** `tag.yml` sees `version:` change on
   `main` and pushes `vX.Y.Z`; the tag triggers `release.yml`, which reruns the
   full gate against the tag, verifies the tag matches the pubspec, and
   publishes with pub.dev OIDC.

Choose the bump with a consumer's `^0.1.0` constraint in mind:

| Bump | Effect pre-1.0 | Use for |
|---|---|---|
| `patch` | `0.1.0` → `0.1.1` | compatible correction or addition |
| `minor` | `0.1.0` → `0.2.0` | substantial compatible work |
| `breaking` | `0.1.0` → `0.2.0` | anything a consumer must react to |

`breaking` rather than `major` while pre-1.0: it advances the minor position,
which is exactly what `^0.1.0` protects against. `major` would jump to `1.0.0`
and claim a stability milestone this package has not made. The dropdown offers
no `major` for that reason.

Contributors maintain the `Unreleased` section with `cider log` as they work,
so `cider release` only dates and links what is already written. The changelog
is never generated from commit messages.

**Read the changelog diff on the release pull request.** It should be two lines:
`## [Unreleased]` becoming `## [x.y.z] - <date>`, and its link definition
becoming the version's. Anything larger means cider re-serialised sections it
could not parse. `checks.yml` fails the pull request in that case, but knowing
the shape of a healthy diff is what makes an unhealthy one obvious.

**0.1.0 has no git tag**, so its link points at pub.dev
(`/packages/eigen_flutter/versions/0.1.0`) rather than a release tag. It was
published by hand before this automation existed, and the tag later created for
it described a tree that never shipped, so it was deleted rather than corrected
and no commit provably matches the published tarball.

One consequence, once only: cider will generate `[0.2.0]:
…/compare/v0.1.0...v0.2.0`, and that comparison cannot resolve. Change that line
to the tag form (`…/releases/tag/v0.2.0`) while reviewing the release pull
request. From 0.2.1 on, both endpoints exist and the generated link is correct.

Generated source remains committed and ships in the package. Consumers never
need this repository's builders to use `eigen_flutter`.

### Why a tag, and why the App token

pub.dev's automated publishing trusts a GitHub OIDC token only when its ref is
a **tag** matching the configured pattern, so publication cannot run on a
branch push and something must create the tag. `tag.yml` keys on `pubspec.yaml`
changing on `main` rather than on the release pull request merging: the
version in the file is the fact, and how it got there does not matter, so a
hand-edited bump releases identically and there is no second path to maintain.

Both workflows push using the **eigen-release** App token rather than
`GITHUB_TOKEN`. A tag pushed by `GITHUB_TOKEN` does not trigger further
workflow runs, so `release.yml` would never fire and the release would stall
with no error anywhere. The same suppression is why the release pull request
needs the App to receive its required checks.

**Both workflows treat pub.dev as the authority on what has been released**, and
neither trusts the local tags for it. `release.yml` skips publication when the
version is already published, so a retried job or a re-pushed tag is harmless
rather than a red release. `tag.yml` applies the same test before creating a tag
at all.

That second check exists because the first release predates this automation.
`eigen_flutter 0.1.0` was published by hand and never tagged, so "no tag" meant
"unreleased" only by accident, and the first `pubspec.yaml` edit afterwards, an
`eigen_api` constraint bump that left `version:` alone, duly tagged an unrelated
commit as `v0.1.0`. Nothing was published, because the skip above held, but the
tag described a tree that never shipped and had to be deleted. A tag that cannot
be trusted to mean what it says is worse than no tag: every later `vX...vY` diff
inherits the error silently.

## Dart API documentation

**pub.dev builds and hosts Dartdoc for every published version.** Nothing here
runs `dart doc` for publication, and no generated HTML is committed or copied
into `eigen-web`. This is deliberate, and the opposite of how the TypeScript
side works: eigen-web vendors generated references from `eigen-server` because
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

- **The gate fails on the release pull request:** fix it on the branch like any
  other pull request. Nothing has been tagged or published yet.
- **`release.yml` fails after the tag exists, before `dart pub publish`:** fix
  the cause on `main`, delete the tag, and re-push it at the corrected commit.

  Do **not** expect re-running the failed run to pick the fix up. A
  tag-triggered run uses the workflow definition **at the tag**, not the one on
  `main`, so re-running replays the same broken file, and if the fault is in
  `release.yml` itself, it will keep replaying it. Deleting and re-tagging is
  the only recovery that reloads the workflow. (This is safe here precisely
  because the version has not been published; never move a tag whose version
  reached pub.dev.)
- **The version was published:** never reuse it. Correct the problem, add a
  changelog entry, and dispatch a new `patch` or `breaking` release.
  Re-triggering the published version is safe but does nothing; `release.yml`
  detects it on pub.dev and skips.
- **A harmful version shipped:** use pub.dev retraction, communicate the
  affected range, and publish the replacement. Published versions cannot be
  overwritten.
- **Dartdoc failed on pub.dev despite the dry run:** inspect the hosted build
  log, correct the documentation source, and publish a new version.

Record exceptional recovery steps in the release notes or a repository issue
so the package, tag, and source history remain reconstructable.
