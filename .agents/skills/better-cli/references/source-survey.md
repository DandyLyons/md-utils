# Better CLI source survey

## Provenance and reuse

- Repository: [BetterCLI/bettercli.org](https://github.com/BetterCLI/bettercli.org).
- Survey date: 2026-10-27.
- Inspected revision: `5ef14f4646c098037084502008f75b73d29cc6d0`.
- Immutable source: [content tree at that revision](https://github.com/BetterCLI/bettercli.org/tree/5ef14f4646c098037084502008f75b73d29cc6d0/content).
- Authors/attribution: BetterCLI/bettercli.org contributors; individual history is
  available in the linked repository. No endorsement of this adaptation is implied.
- Upstream license: [CC BY-SA 4.0 license file](https://github.com/BetterCLI/bettercli.org/blob/5ef14f4646c098037084502008f75b73d29cc6d0/LICENSE).
  This skill's adapted text is also offered under
  [Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/).
  This notice applies to this skill, not the surrounding project's code or documents.
- Changes: paraphrased and reorganized source guidance into task-oriented references;
  replaced incomplete examples; added labeled implementation/verification extensions;
  retained source limitations and omitted historical vendor claims as instructions.

Read all 30 Markdown files under `content/`, including index pages, drafts, and
stubs, plus `content/design/example-help.txt`, root README, and the license.
This is a survey of the repository's written CLI guidance, not an audit of the
website's implementation. Images were identified as illustrations but not used as
independent technical evidence. Outbound articles and vendor tools were not all
audited; their presence in upstream does not make them verified recommendations.
Linked live pages can differ from this pinned source snapshot.

## Findings across the corpus

The central theme is a dual audience: people discovering commands and programs
depending on predictable interfaces. Help must explain purpose and starting points,
while output and statuses must serve automation. The other major theme is installed
software's long life: users control versions and environments, and authors cannot
assume immediate upgrades, permissive networks, or identical machines.

Help, networking, analytics, and lifecycle have the richest reasoning. Distribution
provides useful channel tradeoffs but incomplete platform procedures. Configuration,
messaging, debugging, security, and signing mix actionable advice with unfinished
sections. Completion and framework selection have no substantive recipe. Explicit
drafts offer prompts for thought, not a completed standard.

## Complete inventory

Paths below are relative to the pinned `content/` tree. “Substantial” describes
coverage, not correctness or freshness. “Partial” means substantive text alongside
unfinished content. “Index” means navigation/frontmatter rather than a guide.

| Source path | State and useful coverage | Skill destination |
| --- | --- | --- |
| `_index.md` | Introduction: human and machine audiences; design/how-to/glossary organization | Entrypoint and this survey |
| `design/_index.md` | Index only | Routing context |
| `design/cli-help-page/index.md` | Substantial: purpose, onboarding, generated reference versus authored docs, help invocation, pager, typos; some commented unfinished sections | [Help](help-and-discovery.md) |
| `design/using-colors-in-cli.md` | Substantial: escape formatting, themes, overstrike, non-TTY, `NO_COLOR` | [Output](output-and-automation.md) |
| `design/messaging.md` | Partial: progress and optional silence on success; error section unfinished | [Output](output-and-automation.md) |
| `design/exit-codes.md` | Substantial: contextual success/failure, partial outcomes, simplicity | [Output](output-and-automation.md) |
| `design/configuration.md` | Partial: scope, environment booleans, versioned configuration, executable config, parsing; flags/YAML unfinished | [Configuration](configuration.md) |
| `design/cli-networking/index.md` | Substantial: centralized networking, proxies, trust, authentication, IP families, endpoints, identity headers | [Networking](networking.md) |
| `design/debugging.md` | Partial: shared debug controls, stderr, diagnostic files, sensitive data; tracking sections empty | [Diagnostics](diagnostics-security-performance.md) |
| `design/security-considerations.md` | Partial: publisher control, subprocess risks, operational inventory; SBOM/update sections unfinished | [Diagnostics](diagnostics-security-performance.md), [lifecycle](distribution-and-lifecycle.md) |
| `design/performance.md` | Short substantive overview: startup/install latency, perceived speed, real-world versus synthetic measurements | [Diagnostics](diagnostics-security-performance.md) |
| `design/collecting-analytics/index.md` | Substantial: alternatives, sensitive data, consent tradeoffs, server facade, bounded delivery, version segmentation, tracking links | [Telemetry](telemetry.md) |
| `design/cli-application-lifecycle.md` | Substantial: long-lived versions, user control, channel ownership, upgrade/downgrade, cleanup | [Lifecycle](distribution-and-lifecycle.md) |
| `design/versioning.md` | Short substantive guide: SemVer compatibility, selectable ranges/versions, build identity | [Lifecycle](distribution-and-lifecycle.md) |
| `design/cli-as-sdk.md` | Stub: introductory idea and unfinished sentence, no implementation contract | [Output](output-and-automation.md), explicitly labeled extensions |
| `design/checklist.md` | Explicit draft: brief help/output/install/signing reminders, not comprehensive | [Review](review-and-verification.md), independent synthesis |
| `design/falsehoods-about-cli.md` | Explicit draft: assumptions about access, disks, upgrading, latest versions | [Lifecycle](distribution-and-lifecycle.md), environmental review prompts |
| `design/distribution/_index.md` | Index only | Routing context |
| `design/distribution/installation.md` | Partial: source/binary/package/integration/container tradeoffs; several platform sections incomplete | [Lifecycle](distribution-and-lifecycle.md) |
| `design/distribution/auto-updating-cli.md` | Short conceptual discussion: evolvable clients and simpler upgrade notices; no updater implementation | [Lifecycle](distribution-and-lifecycle.md) |
| `design/distribution/self-executing-installer/index.md` | Partial: convenience versus control, versioning, destination, lifecycle burden, defensive checks; several mechanics unfinished | [Lifecycle](distribution-and-lifecycle.md) |
| `how-to/_index.md` | Index only | Routing context |
| `how-to/implement-shell-autocomplete.md` | Stub: title and TODO only | [Help](help-and-discovery.md), external framework lookup required |
| `how-to/sign-cli-executable.md` | Partial: provenance, certificate lifetime, platform notes; dated details and unfinished sections | [Lifecycle](distribution-and-lifecycle.md), official-source verification required |
| `how-to/format-text.md` | Explicit draft: title only | Use substantive colors article instead |
| `glossary/_index.md` | Index only | Routing context |
| `glossary/manpage.md` | Short definition, common sections, invocation | [Help](help-and-discovery.md) |
| `glossary/terminal-pagers.md` | Short definition, scrolling, pipe/file invocation | [Help](help-and-discovery.md) |
| `glossary/POSIX.md` | Short compatibility definition, not detailed utility syntax rules | Terminology only; no claimed POSIX conformance |
| `glossary/list-of-frameworks.md` | Stub: title and TODO only | No framework recommendation inferred |

Additional content asset: `design/example-help.txt` mixes a fictional file-sync
tool with unrelated Cobra boilerplate and empty sections. Its ordering informs the
help reference; its text is not copied as a finished template. Supporting images
illustrate a pager, proxy metaphor, analytics/version charts, and update notices.

## Interpretation boundaries

- `draft: true` appears on exactly three pages: checklist, falsehoods, and text
  formatting. Other pages can still be incomplete without that flag.
- The source recommends simple exit codes, but leaves task semantics to the CLI.
  It does not mandate replacing an existing status taxonomy with 0/1.
- Silence on success, auto-update, executable configuration, tracking, a pager,
  and insecure TLS bypasses are contextual choices, not required features.
- The configuration article does not establish a precedence hierarchy or settle
  YAML policy. The framework and completion pages cannot justify tool choices.
- The article's broad `NO_COLOR` wording does not settle all current convention
  details. Proxy variables and exclusion matching remain stack-dependent.
- Claims about fixed color rendering, package security, signing costs, and required
  host versions should not be generalized or treated as current guarantees.
- Stable JSON contracts, noninteractive prompt handling, subprocess argument safety,
  and the consolidated verification matrix are this skill's labeled extensions.

## Maintaining the adaptation

When refreshing, inspect a new source revision and compare the full content tree,
not just navigation links: hidden drafts and stub pages may have become substantive.
Record the revision/date, update changed topic references, and revise this inventory.
Verify new links and preserve attribution/license notices. Do not silently upgrade
a draft into mandatory guidance or turn a newly mentioned vendor into a dependency.

Keep the entrypoint short and read references only when relevant. Validate skill
frontmatter and UI metadata; verify every local Markdown link and reference route.
Use the scenarios in [review and verification](review-and-verification.md) to assess
behavior when substantive instructions change. Structural validation alone does
not demonstrate useful or correct agent decisions.
