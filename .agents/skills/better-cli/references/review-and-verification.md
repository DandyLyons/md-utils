# Review and verification

This is an operational synthesis of the routed references, not a reproduction of
the upstream draft checklist. Use it for a broad audit or a targeted test plan.
Do not automatically require every category for a small change.

## Survey the interface

Inventory command groups, common journeys, supported environments, integration
callers, and documented compatibility policies. Identify which statements come
from code, observed execution, tests, documentation, or assumptions. Use safe
fixtures when probing writes or errors; follow local temporary-file policies.

| Area | Questions to resolve | Read |
| --- | --- | --- |
| First use | Can a newcomer understand purpose, prerequisites, and a working example? | [Help](help-and-discovery.md) |
| Automation | Are streams, statuses, formats, prompts, and partial results predictable? | [Output](output-and-automation.md) |
| Configuration | Are scope, precedence, types, and versions explicit? | [Configuration](configuration.md) |
| Networked environments | Are proxy/trust/routing assumptions supported and testable? | [Networking](networking.md) |
| Failure and latency | Can users diagnose failure without exposing secrets or waiting unnecessarily? | [Diagnostics](diagnostics-security-performance.md) |
| Measurement | Is collection needed, disclosed, bounded, and independently failure-tolerant? | [Telemetry](telemetry.md) |
| Installed life | Can users pin, verify, update, downgrade, and remove supported installations? | [Lifecycle](distribution-and-lifecycle.md) |

Mark inapplicable topics explicitly, such as networking for a fully local tool.
Distinguish missing evidence from proven failure. Existing behavior is evidence
about compatibility, not automatic proof of good design.

## Findings that enable action

For each material finding, supply the affected command/file, reproducible trigger,
observed behavior, user or automation impact, recommended change, compatibility
consequences, and a focused validation method. Cite the relevant reference/source
when it explains the recommendation. Prioritize broken contracts, loss of data,
or automation failures above cosmetic consistency. Avoid inflated severity for
preferences such as optional pager use.

For implementation, choose the smallest change that fixes the demonstrated issue.
For design-only requests, deliver a concrete interface proposal with examples and
unresolved decisions. Follow repository approval requirements before significant
behavior changes; do not turn a review into an unrequested migration.

## Representative behavioral checks

Select real commands and capture stdout, stderr, exit status, and filesystem or
network effects as appropriate. Review the relevant parent help when discovery
changes. Verify examples rather than merely searching for their strings in source.
Prefer assertions about observable contracts over brittle full-output snapshots
unless exact formatting itself is the required contract.

Use these scenarios to evaluate whether this skill is being applied sensibly:

1. **Help-only request:** A command's generated help lists flags but never explains
   its task. Improve purpose/examples and inspect executable help. Do not redesign
   status codes or add telemetry as part of the edit.
2. **CI output failure:** JSON output parses locally but fails in CI. Inspect stream
   routing, progress, update notices, and no-input behavior. Preserve the supported
   data schema unless changing it is authorized.
3. **Corporate proxy failure:** An API request fails behind an intercepting proxy.
   Inspect shared routing, proxy variables, and trust roots. Do not make disabled
   certificate verification the default fix.
4. **Upgrade proposal:** A package-managed CLI wants auto-update. Evaluate version
   pinning, channel ownership, configuration downgrade, and unattended operation
   before proposing an updater. A proposal does not authorize installation.
5. **Incomplete upstream topic:** A request asks for completion implementation.
   Report that Better CLI's how-to is a stub, use the target framework's current
   documentation, and test supported shells. Do not invent source-backed steps.

Finish with changes/findings, evidence, and material limitations. Distinguish checks
actually run from suggested follow-up tests. A skill validator checks packaging,
not whether a CLI follows these principles.
