# Pending edits and index apply

`md-utils index apply` applies explicit pending edits through the same native
mutation coordinator used by REST. It does not require an HTTP process. Markdown
files remain authoritative; arbitrary edits to derived SQLite rows are not drafts.

## Stage and inspect intent

Configure a version 3 resource with a writable codec and explicit `patch` and/or
`replace` mutation opt-ins in `.md-utils/server/server.yaml`. Draft commands use
that same configuration and its complete loaded type/rule registries. Select an
alternate file with `--server-config`; select a project with `--project-root ./`.

Save a shared patch envelope in `edits/dune.json`:

```json
{"frontmatter":{"set":{"title":"Dune: reading notes","subtitle":null},"remove":["author"]}}
```

Only explicitly writable fields are accepted during planning. The example assumes
`title`, `subtitle`, and `author` are exposed by the codec. Null stores null; remove
deletes a field. Omitted patch fields remain unchanged. A replacement supplies the
complete writable frontmatter and a body when the codec requires it. Identity
edits, creation, deletion, copy, and move use their existing separate mutation
interfaces rather than draft operations.

```sh
md-utils index query 'SELECT path,hash FROM files' --format jsonl
md-utils index draft add books/Dune.md --resource books \
  --revision '<source-sha256>' --patch-file edits/dune.json
md-utils index draft list
md-utils index draft show '<draft-id>'
md-utils index apply --dry-run
md-utils index apply --dry-run --format jsonl
md-utils index apply
md-utils index draft discard '<draft-id>'
```

Use `--replace-file` instead of `--patch-file` for replacement. Exactly one input
file is required. Its shared JSON mutation envelope is bounded to 8 MiB. The raw
SHA-256 must be the revision against which the edit was authored; staging never
substitutes the latest hash. Staging verifies the source, resource membership,
operation opt-in, and configured UUID. Content/codec validation errors may remain
as a draft for preview; unsupported request envelopes cannot be staged.

One active draft may address a path or configured UUID. Completed drafts can be
discarded; another edit receives a fresh draft ID and baseline. Commands enumerate
at most 10,000 stored drafts and process payloads individually. `list` emits one
JSON draft per line; `show` and `add` emit one JSON object.

## Independent persistence

Version 1 drafts are JSON files under `.md-utils/drafts/`, bounded to 64 MiB when
read. They retain their original path, resource, source SHA-256, optional normalized
persistent UUID and UUID metadata path, configuration fingerprint, provenance
epoch, explicit request, state, and submission/receipt linkage. Folder permissions
are 0700 and draft permissions are 0600. Writes use atomic replacement and syncing.

Refresh, watching, full rebuilds, metadata-only/FTS changes, and JSONB-to-text
rebuilds leave these files unchanged, including conflict and baseline data. Draft
format evolution is independent of disposable cache formats. Legacy
`pending_edits` tables still block rebuild; there is no automatic import of
arbitrary legacy SQLite edits. The draft store is not a source backup.

## Reconcile identity before planning

The original path is a locator; the configured UUID supplies identity evidence;
the source hash is the content precondition. Planning reads authoritative files,
never cached FTS bodies or metadata as source text. Discovery skips hidden entries
and symlinks using the same incremental native traversal adapter as indexing.
Errors or disappearing files fail discovery rather than establishing absence.

| Current evidence | Result |
| --- | --- |
| Original path, UUID, and baseline hash match | Plan the edit. |
| Same target with changed source hash | Stale baseline conflict. |
| Original path now has a different UUID | Target replacement conflict. |
| Multiple current UUID holders | Ambiguity; inspect provenance and select the intended file. |
| UUID appears elsewhere with a confirmed managed move chain | Follow the move after verifying baseline bytes and current resource requirements. |
| UUID appears elsewhere without sufficient managed evidence | Unconfirmed relocation; explicitly review and restage. |
| No current holder after complete discovery | Missing target; retain the unresolved draft. |
| No persistent UUID | Use the original path and exact baseline bytes; do not infer relocation. |

Automatic following requires coordinator-confirmed, chronological moves after
staging, matching baseline revisions, one unambiguous chain (at most 64 moves),
and the same unpruned cache epoch. A rebuilt index loses that evidence while
preserving the draft. Operator-confirmed events do not authorize automatic move
following. Managed copy creates a different UUID and does not redirect the
original's draft. External disappearance and appearance do not prove move versus
deletion/creation. Exact restores between observations can remain undetectable.

External relocation candidates require explicit review: inspect source and
provenance, discard the unsubmitted draft, and stage the intended edit against the
selected current path and revision. No automatic rebase, merge, repair, or source
restoration occurs. Changed resource/registry configuration requires review and
restaging instead of silently interpreting old intent under new rules.

## Preview and commit

Dry-run shares source encoding, complete-record assessment, protected-field policy,
and uniqueness checks with execution. Text output shows exact original/proposed
source and diagnostics; JSONL includes those values, proposed hash, resolution,
and conformance changes. Metadata edits may reserialize frontmatter; body-only
edits preserve its exact bytes. See [codec preservation](resource-mutations.md).

Dry-run does not create or refresh an index, create a writer lock, update draft
states, recover mutations, or create/prune receipts. It uses read-only evidence
queries and bounded authoritative scans. Filesystem traversal is an observation
over time, not an atomic folder snapshot. Preview cannot guarantee a later commit.

Apply selects all noncompleted drafts, or the explicitly supplied draft IDs, in
lexicographic ID order. It holds the shared collection writer lease, recovers
confirmed existing commits, and preflights the selection before new writes. A
known preflight blocker leaves the other drafts unsubmitted. Before each mutation,
it replans against current source; the native coordinator refreshes collection
evidence, validates again, and rechecks the revision during atomic replacement.

Processing retains bounded per-file source, not a corpus-sized body snapshot.
Offline identity/uniqueness planning can traverse the collection for each draft;
large batches therefore require multiple passes. A preview does not simulate
cross-file uniqueness swaps. Later drafts can become invalid after earlier writes
and are rechecked rather than trusting preflight results.

Confirmed success requires refreshed content, every affected scope/membership,
identity, diagnostics, optional FTS, and server publication. Search remains opt-in.
The first execution failure stops subsequent writes and reports completed,
publication-pending, unresolved, and unattempted work. SQLite transactions do not
make multiple filesystem writes atomic; committed files are not rolled back.

## Retry and recovery

Before submission, apply durably stores a stable attempt UUID and resolved path.
The coordinator uses that UUID as its receipt ID and syncs the receipt before
source persistence. A pin under `.md-utils/mutations/pins/` prevents retention
pruning until the draft durably acknowledges completion or abandonment.

| Draft state | Meaning |
| --- | --- |
| pending | Explicit intent has not been submitted. |
| conflict | Apply found a blocker; original baseline/intent remain. |
| submitted | An attempt ID was persisted; inspect its receipt. |
| publicationPending | Source commit is confirmed; retry publication without rewriting source. |
| recoveryRequired | Outcome requires explicit operator resolution. |
| completed | Source persistence and publication completed. |

Restart adopts a completed matching receipt even if draft acknowledgement was
interrupted. Confirmed commits are republished without applying the edit again.
Prepared/indeterminate receipts require the existing explicit recovery contract;
matching proposed bytes alone do not prove commit. Unresolved receipts reserve
both paths of an interrupted move.

```sh
md-utils index draft resolve '<draft-id>' --decision confirmCommitted
md-utils index draft resolve '<draft-id>' --decision confirmNotCommitted
md-utils index apply
```

`confirmCommitted` requires the recorded proposed outcome. `confirmNotCommitted`
requires baseline source and abandons the attempt without rewriting source. The
draft then becomes pending with its original baseline. If its receipt is missing,
only explicit `confirmNotCommitted` with matching baseline source can reset it;
apply never blindly resubmits it. Submitted unresolved drafts cannot be discarded.
Recovery may publish index changes but does not reapply the patch. See
[native mutation recovery](rest-mutations.md).

## Validation

```sh
swift test --filter 'MarkdownDraftTests|IndexApplyCommandsTests|MarkdownMutationTests|CollectionIndexerTests'
swift build
swift test
```

Tests cover metadata-only/FTS parity, dry-run byte-for-byte storage preservation,
stale baselines and final commit checks, moves/copies/replacements/missing targets,
codec preservation, actual draft survival through rebuild/mode changes, overlapping
resources, interrupted multi-file work, and explicit recovery. Linux validation
runs in CI only.
