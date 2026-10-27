# Telemetry

## Source basis

Adapted from [Collecting analytics](https://bettercli.org/design/collecting-analytics/).
The article explores tradeoffs rather than mandating tracking or a consent model.
Its preference for opt-out in some situations is not a universal policy. Legal
obligations require current authoritative guidance when actually relevant; this
reference does not establish legal compliance.

## Decide whether collection is needed

Telemetry should never be added to the CLI unless it is an explicit requirement for
the project.

Start with the question to answer: feature adoption, version exposure, failure
rates, or performance changes. Existing API metrics or distribution statistics may
provide enough visibility without a new client event channel. Recognizable client
version information can help, but download counts are not active users and all
observations have sampling limitations.

Do not add tracking as part of an unrelated CLI improvement. When telemetry design
is requested, make data fields, destinations, retention, and user controls explicit.
Respect the chosen consent policy; do not infer permission from silence or from
upstream examples. Review changes to existing collection separately from local
debugging behavior.

## Minimize and control data

Treat all user input and machine/network metadata as potentially sensitive, even
apparently harmless paths, repository names, and error strings. Collect only
fields needed for the stated purpose. Prefer predefined event/error categories
over arbitrary raw text when they answer the question.

Provide server-side filtering and sanitization so already-released clients can
be handled. Establish deletion/purge procedures for accidental collection. A new
client release cannot retract data emitted by old binaries.

Prefer a publisher-controlled facade endpoint to direct calls into a third-party
analytics vendor. It centralizes filtering, enables provider changes, and limits
additional firewall destinations. An unauthenticated event endpoint also needs
abuse and payload controls; events from clients are not inherently trustworthy.

## Keep command execution independent

Collect only after the command's main work when possible. Optional telemetry
must not prevent useful work, turn a success into failure, or indefinitely delay
process exit. Bound network time and avoid retries that prolong an offline run.
If connectivity is already known to be unavailable, skip the optional call.
Use the shared network policy, including proxies and trust configuration.

Extension: define cancellation and shutdown behavior in the runtime. A background
task may be abandoned when the process exits; guaranteed delivery is often a poor
tradeoff for CLI responsiveness. Prefer bounded best effort unless requirements
justify a separate, explicit delivery design.

## Interpret results and links

Segment error/performance data by version and platform; aggregate rates can hide
a severe regression in a newly released version. Account for older clients,
network blocking, collection choices, and changes in the event schema.

Upstream discusses tracking parameters and shortened links in terminal output.
Treat these as optional product choices, not a recommendation to obscure link
destinations. If chosen, favor readable stable links on a trusted controlled
domain and make collection consistent with the stated privacy policy.

## Verification (extension)

Check collection disabled, enabled, offline, proxy failure, slow/unreachable
endpoint, server rejection, and old event versions. Confirm disabled collection
does not contact the endpoint and optional failures do not corrupt stdout or
change command outcomes. Inspect representative payloads for unintended data.
