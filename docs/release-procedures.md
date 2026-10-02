# Release Procedures

The [platform/build guide](building-and-platforms.md) describes support and CI
coverage. macOS users build from source or use Mint. Ubuntu 24.04 ARM64 has an
automated CLI prerelease archive workflow. There is no automated binary release
for macOS, Linux x86_64, `md-utils-server`, or WebAssembly.

## Versions and release preparation

The first Linux preview is planned as **`0.3.0-linux.1`**. It does not reconcile
historical release numbering or complete the config-format work in
[#135](https://github.com/DandyLyons/md-utils/issues/135). Config/schema versions
are independent of CLI artifact versions: project config 0.3.0 is opt-in,
`config init` and the `latest` schema alias remain at 0.2.0. See
[config 0.3](config-v0.3.md). Do not retag an existing release.

The CLI reads `Sources/md-utils/Resources/BuildVersion.txt`. Native source/Mint
builds use the checked-in value, currently `0.3.0-linux.1-dev`. The Linux workflow
stamps the exact prerelease tag for tagged builds and
`0.3.0-linux.1-dev.<12-character-commit>` otherwise. A Git tag alone does not
stamp source/Mint builds; update the resource in the release commit when preparing
a future general source release. The packaging script currently accepts only
`0.x.y-<prerelease>` versions, so a stable release needs a deliberate packaging
policy update before Linux binaries can accompany it.

Before tagging a candidate on `main`:

- [ ] Confirm the intended changes are merged and the working tree is clean.
- [ ] Review changes from the previous release and document breaking changes.
- [ ] Run `swift build` and `swift test` with a matching native compiler/SDK.
- [ ] Confirm relevant Linux, SQLite, server, and WASI CI checks pass for the candidate.
- [ ] Update public API documentation, CLI help, README, and platform/release guidance.
- [ ] Check the intended CLI version separately from schema versions.
- [ ] For binaries, preserve SwiftPM resources, dependency notices, and corresponding source.

Use `gh release list` and `git tag --sort=-v:refname` to select an explicit previous
tag, then review `git log <previous-tag>..HEAD --oneline` and
`git diff <previous-tag>..HEAD --stat`. Choose a new, unused version. The project
uses `0.x.x` SemVer releases; breaking changes can occur between minor versions
and must be described in release notes.

## Publish the Linux ARM64 preview

Require the **Linux ARM64 CLI distribution** workflow to pass for the candidate,
including clean runtime installation and offline source/JXKit rebuilding.
Linux validation runs in CI only. PR, main-branch, and manual runs produce CI
artifacts retained for 14 days; they are not published releases.

Once the candidate is verified, tag that commit (these commands assume it is
checked out):

```sh
git tag 0.3.0-linux.1
git push origin 0.3.0-linux.1
```

The tag-push workflow verifies the tagged build again, then publishes these four
assets without rebuilding them in the publication job:

- `md-utils-0.3.0-linux.1-linux-aarch64-ubuntu24.04.tar.gz`
- `md-utils-0.3.0-linux.1-linux-aarch64-ubuntu24.04.tar.gz.sha256`
- `md-utils-0.3.0-linux.1-source.tar.gz`
- `md-utils-0.3.0-linux.1-source.tar.gz.sha256`

Let the workflow create the GitHub release; do not race it with manual
`gh release create`. It marks the release **prerelease**, with **latest disabled**.
Only the publication job has release-write permission. Manual dispatch, even on
a tag, does not publish. Existing assets are never silently overwritten, and an
existing stable release is rejected. Investigate partial publication before any
retry; use a fresh prerelease version if artifact contents need to change.

After publication, verify the prerelease flag, all four assets, and the downloaded
archives' checksums. Follow the pinned
[downstream installation example](linux-arm64-distribution.md) to confirm the
published binary's version and resources in CI. Keep matching source archives
available alongside every binary, beyond CI artifact expiration.

The archive links Swift statically and uses Ubuntu system shared libraries. It
preserves SwiftPM resources, Swift/Knap/Day.js and other dependency notices, and
JXKit's LGPL source/relinking materials. See the [source rebuild guide](../scripts/release/REBUILD.md).
Dynamic system JavaScriptCore linkage does not replace JXKit's separate
requirements. Packaging does not assign a new license to md-utils.

## General source releases and Mint

For a future general source release, first complete the checklist and commit the
intended `BuildVersion.txt` value. A stable tag does not trigger the current Linux
prerelease workflow. After pushing the new tag, choose one way to create its
GitHub release, for example:

```sh
# Replace 0.x.y with the selected, already-pushed tag.
gh release create 0.x.y --verify-tag --generate-notes
```

Alternatively, write reviewed notes to a project-local file such as
`tmp/release-notes.md` and use `--notes-file tmp/release-notes.md` instead of
`--generate-notes`. Add `--draft` to review before publishing. These manual
instructions are separate from the automated Linux prerelease path above.

Mint clones and builds source; it does not download the Linux binary archive.
It requires the native Swift build prerequisites. Pin a published source tag
when reproducibility matters:

```sh
mint install DandyLyons/md-utils@0.x.y
```

GitHub's automatic repository source downloads are not substitutes for the
Linux workflow's corresponding-source archive, which also includes exact
dependency and recursive submodule Git bundles and rebuilding instructions.

## Publishing JSON schemas

Bundled files in `Sources/md-utils/Resources/` are canonical. Generate and
validate public copies with:

```sh
python3 scripts/sync-schema-publication.py
python3 scripts/validate-schema-publication.py
```

The 0.1.0 and 0.2.0 named aliases are generated for compatibility. Existing
versioned URLs are immutable; add a new versioned directory for changes. The
schema-validation and Pages workflows handle website/schema publication
separately from executable releases. Do not advance schema defaults or aliases
merely because a CLI prerelease is published.
