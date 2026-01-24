# Development Workflow

## Adding New Features

When adding new features:

1. Start with library implementation in MarkdownUtilities
2. Add comprehensive tests using Swift Testing
3. Add CLI command in md-utils (if user-facing)
4. Update CLAUDE.md or relevant docs if architecture changes

## Before Committing

Run these commands to ensure quality:

```bash
# 1. Ensure clean build
swift build

# 2. All tests must pass
swift test

# 3. Verify CLI works
swift run md-utils --help
```

## Checklist

- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] CLI help displays correctly
- [ ] Documentation updated if needed
