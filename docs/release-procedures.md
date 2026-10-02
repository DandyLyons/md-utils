# Release Procedures

## Overview

md-utils is distributed via [Mint](https://github.com/yonaskolb/Mint). Releasing a new version requires tagging a commit on `main` with a semantic version tag and creating a GitHub release.

Builds require Swift 6.3. Template consumers use SwiftKnap; follow its
[third-party distribution notices](https://github.com/DandyLyons/SwiftKnap/blob/main/ThirdParty/README.md)
when distributing binaries. Include the dependency license notices, preserve SwiftPM
resource bundles, and meet the applicable JXKit source/relinking requirements.
Dynamic system runtime linkage alone does not cover JXKit's separate license.
Ubuntu 24.04 installations need `libjavascriptcoregtk-4.1-0`; building also needs
`libjavascriptcoregtk-4.1-dev` and `pkg-config`. See [template rendering](template-rendering.md).

## Pre-Release Checklist

### Linux ARM64 preview

The first Linux artifact uses `0.3.0-linux.1`, independently of config/schema
versions and the eventual stable 0.3 release. The Linux workflow currently accepts
only `0.x.y-<prerelease>` versions. Do not retag an existing release.

Before publishing, require the `Linux ARM64 CLI distribution` workflow to pass
for the candidate commit, including clean runtime installation and offline
source/JXKit rebuild. Follow the CI verification commands in
[Linux ARM64 distribution](linux-arm64-distribution.md). Linux validation runs
in CI only. The tag workflow publishes the verified binary/source archives and
their SHA-256 files as a GitHub prerelease; it does not mark it latest. For these
tags, let the workflow create the release instead of racing it with `gh release create`.
Only the publication job has release-write permissions. Existing assets are never
silently overwritten. Keep matching source archives available with binary assets.

```sh
git tag 0.3.0-linux.1
git push origin 0.3.0-linux.1
```

The binary version resource is stamped from the tag during packaging. This does
not change any schema version or schema initialization default.

### General checklist

Before releasing, complete every item:

- [ ] All feature branches are merged to `main`
- [ ] `swift build` succeeds with no warnings
- [ ] `swift test` passes (all tests green)
- [ ] New public API has documentation comments
- [ ] Breaking changes (if any) are noted for the release description
- [ ] `AGENTS.md` and docs are up to date with any new commands or features
- [ ] You are on the `main` branch with a clean working tree (`git status` shows nothing)
- [ ] `main` is up to date with the remote (`git pull`)
- [ ] `README.md` is updated with any new features or usage instructions
- [ ] Each help page in the `md-utils` is up to date (`abstract` and `discussion` properties in `Command` conformances are updated)

## Deciding the Version Number

Follow [Semantic Versioning](https://semver.org/):

| Change type | Version bump | Example |
|---|---|---|
| Bug fixes, patches | `0.x.Y` | `0.3.1` -> `0.3.2` |
| New features or breaking changes (while `0.x.x`) | `0.X.0` | `0.3.2` -> `0.4.0` |

## Reviewing Changes Since Last Release

Before writing release notes, review what has changed since the last tagged release.

### Find the latest release tag

```bash
gh release list --limit 1
```

Or list all tags:

```bash
git tag --sort=-v:refname
```

### Diff against the last release

```bash
# Summary of changed files
git diff 0.x.y..HEAD --stat

# Full diff
git diff 0.x.y..HEAD

# Commits since last release (most useful for writing notes)
git log 0.x.y..HEAD --oneline

# Commits with more detail
git log 0.x.y..HEAD --format="%h %s"
```

Replace `0.x.y` with the previous release tag (e.g. `0.3.1`).

### View merged PRs since last release

```bash
gh pr list --state merged --search "merged:>$(git log -1 --format=%aI 0.x.y)"
```

Use this output to identify new features, bug fixes, and breaking changes for the release notes.

## Creating a Release with `gh` CLI

### 1. Tag the commit

```bash
git tag 0.x.y
git push origin 0.x.y
```

### 2. Create the release with auto-generated notes

```bash
gh release create 0.x.y --generate-notes
```

This generates release notes from merged PRs and commit messages since the previous tag.

### 3. Create the release with a custom title

```bash
gh release create 0.x.y --generate-notes --title "v0.x.y - Short Description"
```

### 4. Create the release with hand-written notes

```bash
gh release create 0.x.y --title "v0.x.y" --notes "$(cat <<'EOF'
## What's New

- Added `foo` command
- Improved performance of `bar`

## Breaking Changes

- Renamed `baz` to `qux`
EOF
)"
```

### 5. Draft a release (publish later from GitHub UI)

```bash
gh release create 0.x.y --generate-notes --draft
```

### Useful `gh release` Options

| Flag | Purpose |
|---|---|
| `--generate-notes` | Auto-generate notes from PRs/commits |
| `--title "..."` | Set the release title |
| `--notes "..."` | Provide release notes inline |
| `--notes-file CHANGELOG.md` | Read notes from a file |
| `--draft` | Create as draft (not published) |
| `--prerelease` | Mark as pre-release |
| `--latest` | Explicitly mark as latest release |
| `--verify-tag` | Abort if the tag doesn't already exist |

## How Mint Installation Works

Mint installs packages by cloning the repo at the specified tag, resolving dependencies, and building the executable product defined in `Package.swift`. No additional packaging or registry publishing is needed.

Users install with:

```bash
mint install DandyLyons/md-utils
```

Or pin a specific version:

```bash
mint install DandyLyons/md-utils@0.x.y
```

## Versioning Policy

- The project follows [Semantic Versioning](https://semver.org/)
- While on `0.x.x`, breaking changes may occur between minor versions
- Breaking changes are documented in release notes

## Publishing JSON Schemas

Bundled files in `Sources/md-utils/Resources/` are the canonical source for
each schema version. Generate and validate public copies with:

```bash
python3 scripts/sync-schema-publication.py
python3 scripts/validate-schema-publication.py
```

The 0.1.0 and 0.2.0 named aliases are generated for compatibility. Existing
versioned URLs are immutable; add a new versioned directory for changes.
