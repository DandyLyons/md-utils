# Development Workflow

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

# 3. Verify Core on Linux when changing Core or its dependencies
docker build --file Dockerfile.core-linux --tag md-utils-core-linux .

# 4. Verify Core on WebAssembly when changing Core or its dependencies
scripts/build-wasm.sh

# 5. Verify CLI works
swift run md-utils --help
```

## Checklist

- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] Linux Core container passes when Core or its dependencies changed
- [ ] WebAssembly Core build and smoke test pass when Core or its dependencies changed
- [ ] CLI help displays correctly
- [ ] Documentation updated if needed
