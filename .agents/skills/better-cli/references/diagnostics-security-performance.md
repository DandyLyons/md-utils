# Diagnostics, security, and performance

## Source basis

Adapted from [Debugging](https://bettercli.org/design/debugging/),
[Security considerations](https://bettercli.org/design/security-considerations/),
and [Performance](https://bettercli.org/design/performance/). Debugging and security
contain incomplete sections; the practices explicitly marked as extensions below
fill operational gaps without claiming upstream mandates.

## Useful diagnostics

Offer consistent debug/verbose controls across relevant commands, without stealing
an established short flag. Send extra execution detail to stderr. Separate normal
failure explanations from developer detail so users can recover without reading
a stack trace.

Diagnostic files can preserve evidence of intermittent or long-running failures.
If producing one, disclose its location and include useful timing, version, and
execution context. Avoid silently leaving logs in the working directory: they can
disrupt automation or enter commits and shared storage. Follow the project's
approved temporary-file policy; upstream examples using a system temporary path
are illustrative, not authority to override it.

Treat arguments, paths, repository names, environment values, headers, and stack
traces as potentially sensitive. Extension: select safe diagnostic fields, redact
known credentials before formatting, bound retention, and use suitable file
permissions. A redaction pattern is not proof that a support bundle contains no
secrets. Do not upload one without authorization.

## Predictable security boundaries

Inventory installation/configuration/cache locations, system dependencies, and
network destinations so operators can audit the CLI. Where practical, minimize
unnecessary third-party calls and use stable publisher-controlled endpoints.
Version artifacts and configuration deliberately. Ownership of a domain is not
itself proof of artifact authenticity; see [distribution](distribution-and-lifecycle.md).

Review shelling out, privilege elevation, and destructive operations involving
user input. The CLI may run on a remote machine with different permissions and
consequences than a developer laptop.

Extension: pass subprocess arguments as argument arrays rather than interpolating
shell text; use the least privileges needed; make destructive scope explicit;
and check overwrite/partial-write behavior. These are focused implementation
checks, not a requirement to introduce confirmation dialogs to every command.

## Measure responsiveness

Distinguish installation time, startup latency, time to first useful feedback,
and total work duration. Fast rejection of a mistyped argument can matter more
than a small improvement to a long task. Progress improves perceived performance
only when honest and compatible with automation.

Benchmark representative code paths, datasets, and settings. Keep comparisons
under similar conditions and record platform, version, and input size. Synthetic
or CI timings can reveal regressions, but host load makes them noisy. Extension:
measure repeated runs and cache conditions when those affect the conclusion.

User timing telemetry can show trends across versions/platforms, but is neither
required nor an automatic part of optimization. Apply the separate
[telemetry reference](telemetry.md) only when that work is in scope. Do not add
tracking to diagnose a local performance problem.

## Evidence to collect (extension)

Verify clean machine output with debug enabled, useful failure context, redaction
of representative secrets, disclosed log paths, bounded logging, and behavior
without write permissions. Measure startup/help and relevant workload latency.
Use safe fixtures for subprocess and mutation tests; do not exercise destructive
cases against real user data.
