# Release Procedures

## Overview

md-utils is distributed via [Mint](https://github.com/yonaskolb/Mint). Releasing a new version requires tagging a commit on `main` with a semantic version tag.

## Prerequisites

Before releasing, ensure:

1. All changes are merged to `main`
2. `swift build` succeeds
3. `swift test` passes
4. Breaking changes (if any) are documented in the release notes

## Release Steps

1. **Decide the version number** following [Semantic Versioning](https://semver.org/):
   - `0.x.0` for new features or breaking changes (while on `0.x.x`)
   - `0.x.y` for bug fixes and patches
2. **Tag the commit on `main`**:
   ```bash
   git tag 0.x.y
   git push origin 0.x.y
   ```
3. **Create a GitHub release** (optional but recommended):
   ```bash
   gh release create 0.x.y --generate-notes
   ```
   Edit the generated notes to highlight breaking changes if applicable.

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
