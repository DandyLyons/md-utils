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
5. Update the agent skill for user-facing CLI changes, following
   [Maintaining the Agent Skill](../AGENTS.md#maintaining-the-agent-skill).

## CLI Changes and Agent Skill Documentation

Apply the skill-maintenance procedure to changed or removed behavior as well as
new commands, including shared-library changes that affect the CLI. Update the
relevant canonical `references/` file with detailed guidance. Keep `SKILL.md` for
introductions, routing, and shared constraints; synchronize the complete bundled
folder after any canonical skill change, including reference-only edits.

Verify affected examples against the current executable using project-local
fixtures, check reference links and discoverability, and record the results in
review notes. If no skill documentation needs changing, explain why.
`AgentCommandsTests` checks every bundled file and complete export. Agent Skill CI
checks synchronization, routing, command coverage, and executable workflows. See
[the audit and coverage matrix](agent-skill-audit.md) for verification limits.

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
- [ ] CLI behavior changes reflected in the relevant skill references, or a concrete reason no update is needed recorded
- [ ] Skill introductions/routing updated when needed; changed reference links and representative examples verified
- [ ] Complete canonical skill synchronized with `scripts/sync-agent-skill.py`; routing, examples, and `AgentCommandsTests` passed for skill changes
- [ ] Skill documentation changes and verification recorded in review notes
