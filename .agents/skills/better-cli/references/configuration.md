# Configuration

## Source basis

Adapted from [Configuration](https://bettercli.org/design/configuration/) and
[CLI application lifecycle](https://bettercli.org/design/cli-application-lifecycle/).
The configuration page has empty arguments/flags content and incomplete format
discussion. It prescribes neither universal precedence nor a preferred format.
The decision procedure below extends its principles.

## Specify sources and scope

Distinguish shared settings from per-invocation settings. Inventory arguments,
environment variables, local/global files, and remote settings actually supported.
Document locations, defaults, scope, and interaction.

Extension: specify precedence and treatment of explicit empty values, false,
absence, arrays, and nested objects. Flags over environment over project config
over user config over defaults is one possible policy, not a Better CLI rule.
Preserve an intentional existing order. Consider a redacted view of effective
values and their sources when diagnosis otherwise involves guesswork.

Prefer conventional uppercase application environment names. Proxy variables have
ecosystem-specific handling; see [networking](networking.md). For boolean variables,
document either presence-based behavior or an explicit accepted vocabulary. Handle
promised case/values consistently and diagnose invalid input. Never accidentally
treat the string `false` as true through generic truthiness.

## Parse defensively

Treat typed configuration as untrusted input. Decide whether `1000.00`, `1_000`,
`-1000`, and `1e3` are legal for each numeric setting. Specify units and bounds.
Diagnose the setting without exposing secrets. Validate paths and URLs according
to the needed operation without rejecting unfamiliar but supported forms.

Choose formats for audience, tooling, diffability, portability, and evolution.
Better CLI mentions JSON, XML, TOML, simple text, and configuration languages;
its incomplete YAML discussion supports no blanket rejection or endorsement.
Use a configuration version when needed, with an explicit unknown-version policy.

Executable configuration adds flexibility and responsibilities for execution,
debugging, versioning, and documentation. Do not introduce it merely because the
source mentions it; respect declarative-only requirements. Extension: avoid
evaluating code from an untrusted working directory during discovery.

## Compatibility tests (extension)

Check supported sources individually, then conflicting settings. Include false
versus absent, empty versus absent, invalid types, and useful source locations.
For versioned files, check old configurations on new readers and future versions
on older supported readers. Normal reads should not silently rewrite files or
destroy downgrade information unless explicitly designed and documented.
