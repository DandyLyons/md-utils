# Development Workflow

Start with [building and platform support](building-and-platforms.md) for native
toolchains, resource installation, and CI coverage. Use
[release procedures](release-procedures.md) when preparing a tagged release.

## Adding New Features

When adding new features:

1. Start content-only implementation in `MarkdownUtilitiesCore`; use `MarkdownUtilities` only for native integrations
2. Add comprehensive tests using Swift Testing
3. Add CLI command in md-utils (if user-facing)
4. Update `AGENTS.md` or relevant docs if architecture changes

## Before Committing

Run these commands to ensure quality:

```bash
# 1. Ensure clean build
swift build

# 2. All tests must pass
swift test

# 3. With the matching Swift 6.3.1 toolchain and WASI SDK installed,
# verify Core on WebAssembly when changing Core or its dependencies
scripts/build-wasm.sh

# 4. Verify CLI works
swift run md-utils --help
```

Linux Docker builds and validation run in CI only.
The ordinary native build/test commands use Swift 6.3 or later; the WASI command
has stricter matching-version requirements. See [WASI setup](webassembly.md).

## Checklist

- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] WebAssembly Core build and smoke test pass when Core or its dependencies changed
- [ ] CLI help displays correctly
- [ ] Documentation updated if needed
