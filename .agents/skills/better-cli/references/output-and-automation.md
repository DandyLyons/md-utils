# Output and automation

## Source basis

Adapted from [colors and formatting](https://bettercli.org/design/using-colors-in-cli/),
[exit codes](https://bettercli.org/design/exit-codes/),
[messaging](https://bettercli.org/design/messaging/), and
[debugging](https://bettercli.org/design/debugging/). Messaging and debugging have
unfinished sections. Structured output, prompt handling, and the test matrix below
are extensions, not a specification from the stub
[CLI as SDK](https://bettercli.org/design/cli-as-sdk/) page.

## Define streams and outcomes

Reserve stdout for requested results and explicit help; route diagnostics and
debug logs to stderr. A completed mutation may need no success message. Choose
feedback according to whether users need a result, confirmation, or recovery
information; silence is not required for every successful operation.

Use zero for successful completion and nonzero for failure according to documented
command semantics. Start simply when designing a new interface. Preserve meaningful
existing exit codes; Better CLI's preference for simplicity does not justify
collapsing an established status contract.

Separate these questions: did the operation execute, what did it find, and did every
item complete? Validation findings, no search matches, HTTP error responses, and
partial batches need deliberate command-specific policies. Explain partial results
and failed items instead of relying on an opaque number. Messages and structured
details carry information exit status cannot.

## Terminal rendering

Disable automatic color and terminal control sequences when the destination is
not a terminal. Inspect the actual destination stream: stdout can be redirected
while stderr remains interactive. Honor `NO_COLOR` through a documented policy;
consult its current specification before deciding empty-value or explicit-override
semantics, which the upstream article does not fully address.

Keep meaning understandable without color. Account for light/dark themes and
contrast; consider foreground and background together. Do not assume extended
colors look identical on every renderer. Avoid legacy overstrike formatting that
becomes duplicated letters in plain text.

Progress can improve slow interactive tasks, but should not become final result
data or pollute redirected output. Extension: use a percentage only when its
denominator is meaningful; otherwise show honest phase/activity feedback. Leave a
legible terminal after completion, failure, and cancellation.

## Automation contract (extension)

- If machine output is warranted, provide an explicit structured format with
  documented shape, ordering expectations, empty results, and partial failures.
  Keep banners, progress, and update notices out of its payload.
- Distinguish readable display changes from schema changes consumed by scripts.
  A human table need not become a permanent parsing API.
- Avoid prompts when input is redirected or unavailable. Provide a documented
  noninteractive path or actionable failure. A `--yes` flag need not authorize
  every destructive operation.
- State the failed operation, useful cause/context, and recovery step. Redact
  secrets; do not present a stack trace as the only user explanation.
- Define interruption, closed-pipe, and partial-write behavior for the target
  runtime where relevant; do not invent universal numeric statuses for them.

## Verify observable behavior

| Situation | Evidence |
| --- | --- |
| Terminal, redirected stdout, redirected stderr | Correct streams and formatting |
| `NO_COLOR`, light/dark display, narrow width | Legible output without color dependence |
| Explicit help versus malformed invocation | Status, destination, no work performed by help |
| Empty result, normal result, invalid input | Documented status and payload |
| Partial batch and interrupted operation | Honest completion/recovery information |
| Structured mode plus verbose/debug | Parseable stdout with separate diagnostics |
| No stdin/CI-like invocation | No indefinite prompt or pager |

Select cases relevant to the requested change and existing contract.
