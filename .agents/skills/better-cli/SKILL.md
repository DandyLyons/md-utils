---
name: better-cli
description: Design, review, and improve command-line interfaces using Better CLI guidance. Use for CLI help, command UX, output and exit contracts, configuration, networking, diagnostics, telemetry design, and installation or upgrade workflows. Not for merely running an existing command or general library refactoring.
license: CC-BY-SA-4.0
---

# Better CLI

Help people discover a command, accomplish their task, recover from failure, and
use the same interface reliably in automation. Apply the guidance to the user's
requested scope and the CLI's audience, rather than adding every possible feature.

## Workflow

1. Inspect affected commands, parser definitions, actual help, tests, and documented
   compatibility promises. Identify interactive and automated callers. For a new
   CLI, establish representative tasks and intended environments.
2. Read only the topic references needed below. For a broad survey, use the review
   reference to select applicable topics; record topics that do not apply.
3. Explain concrete problems with reproducible examples. Distinguish an observed
   defect, a compatibility tradeoff, and an optional improvement. For design work,
   specify inputs, outputs, failure behavior, and examples before implementation.
4. Implement within authorized scope, preserving established contracts unless
   changing them is part of the request. Follow local approval requirements for
   significant syntax, default, output, or exit-status changes. An audit alone does
   not authorize those changes, installations, telemetry, or release publication.
5. Verify affected behavior through the executable when available. Check streams
   and exit status as well as wording. Report what was tested and what remains
   unverified; prose review does not prove runtime behavior.

## Read by task

| Task | Reference |
| --- | --- |
| Help, onboarding, examples, discovery, manuals, completion | [Help and discovery](references/help-and-discovery.md) |
| Colors, progress, stdout/stderr, machine output, errors, status | [Output and automation](references/output-and-automation.md) |
| Flags, environment, config files, precedence, parsing | [Configuration](references/configuration.md) |
| Proxies, TLS, endpoint overrides, network compatibility | [Networking](references/networking.md) |
| Debug logs, security boundaries, latency and profiling | [Diagnostics, security, and performance](references/diagnostics-security-performance.md) |
| Usage measurement, privacy, event delivery and dashboards | [Telemetry](references/telemetry.md) |
| Packaging, signing, installers, upgrades, downgrades, versioning | [Distribution and lifecycle](references/distribution-and-lifecycle.md) |
| Broad audit, verification plan, prioritization, review scenarios | [Review and verification](references/review-and-verification.md) |
| Provenance, complete content survey, gaps, refreshing this skill | [Source survey](references/source-survey.md) |

## Interpretation

Better CLI is contextual design guidance, not a normative specification. References
paraphrase it and label implementation extensions and incomplete source material.
Do not invent upstream requirements for missing sections or copy illustrative
flags into a real CLI without checking support. Verify current platform/tool
instructions from official documentation when needed; this skill is not a frozen
installation or signing manual.

This skill adapts work by BetterCLI/bettercli.org contributors under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Attribution,
revision, adaptation details, and license scope are in the
[source survey](references/source-survey.md). No upstream endorsement is implied.
