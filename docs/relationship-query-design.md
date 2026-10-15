# Scoped relationship queries (#188)

Status: implemented, 2026-10-15. Extends #169 and the
existing [named relationship design](relationship-design.md). RFCs 0001–0004
continue to own type, rule, scalar and recursive relationship semantics.
The broader claims-first model in #186 remains separate design work.

## Selection and applicability decisions

- Keep explicit `rel out|in|both` and their long forms; no default direction.
  `in` works as an ordinary command argument in Bash and Zsh (verified locally).
- Require `--root`. Selection chooses result documents, not the incoming-source
  discovery boundary or destination namespace.
- Supplied file sets contain documents inside that root. Other commands may
  compose the lists; this does not authorize remote retrieval or outside-root
  sources. Endpoints outside selection may still be inside the root.
- `--select-required-type` selects unconditional positive rule requirements:
  direct requirements and requirements shared by every alternative. Merely
  mentioning a type in an alternative is insufficient; negative references do
  not qualify. Named discovery may inspect positive alternative declarations,
  retaining conditional applicability rather than claiming an unconditional
  requirement. Use structural expression analysis, not arbitrary logical inference.
- Without `--type`, discover named applicability from structural conformance,
  matching-rule requirements and explicit hints. Preserve failed required/hinted
  assertions and verification evidence. Explicit `--type` restricts named
  discovery to the requested declaring contracts; ordinary links remain available.
- `--relation` filters named interpretations while ordinary links remain visible.
  Filtering an interpretation must not relabel its occurrence as unnamed.
  Require explicit `--type` for `--relation` to avoid ambiguous automatically
  discovered relation names (approved 2026-10-15).
- Reuse existing JMESPath compilation, execution and truthiness infrastructure
  against the issue's document envelope. Evaluation errors produce unknown
  membership, not silent exclusion. Do not change `fm search`'s input contract.
  TOML skips concern this selector, are reported explicitly, and alone do not fail.

## Progressive disclosure: approved output contract

All three formats—default human-readable text, `--json`, and `--yaml`—support:

| Option | Purpose | Contents |
| --- | --- | --- |
| `--detail summary` (default) | Answer the relationship question | Direction, named semantic triples, ordinary links, brief concern hints |
| `--detail explain` | Explain the answer | Summary plus source locations, applicability, validation findings, completeness reasons |
| `--detail evidence` | Inspect full evidence | Explain plus occurrence/interpretation tables, authored values, syntax, identities/revisions, declaration locations, ranges, candidates and assessment dependencies |

Detail changes presentation only, never query scope, assessment, budgets or exit
status. An incomplete summary stays a summary. Never automatically expand it.
JSON/YAML use one versioned envelope for one or many selected files, with a
`detail` discriminator and documented detail-dependent fields. Do not serialize
the full evidence graph at summary detail. This supersedes #188's original
always-detailed envelope proposal. This feature is unreleased: no legacy-output
mode or migration machinery is required.

Summary presents declared relationships, not verified domain truth. Endpoints
retain document paths as identifiers; richer logical-entity identity is #186 work.
Predicate labels must identify their binding unambiguously. Ordinary links are
separate and acquire no inferred domain meaning. Direction is the query viewpoint;
incoming display does not reverse an authored triple or invent reciprocity.

Repeated equivalent triples may be grouped with `occurrenceCount` in summary;
evidence always preserves individual occurrences. Failed conformance does not
hide a resolved triple. Malformed/unresolved/ambiguous assertions cannot create
fabricated triples; summary retains a short notice/count with a detail hint.
Include selected files with no results, and omit unrequested directions.

### Summary examples

```text
books/example.md

Outgoing
  books/example.md —Book:author→ people/alice.md
```

Only when relevant, append short notices such as:

```text
Search incomplete; more relationships may exist. Use --detail explain.
Relationship validation found issues. Use --detail explain.
2 assertions could not be resolved. Use --detail explain.
```

Complete empty incoming results say:
`No incoming relationships or ordinary links found in this scope.`
Incomplete empty results qualify the inspected scope and add the short hint;
they never imply proven absence.

Summary JSON (predicate names are qualified by the registry's unique declaring
type name; full resource/revision bindings are retained at evidence detail):

```json
{
  "schemaVersion": 1,
  "detail": "summary",
  "direction": "outgoing",
  "selected": ["books/example.md"],
  "relationships": [
    {
      "subject": "books/example.md",
      "predicate": "Book:author",
      "object": "people/alice.md",
      "occurrenceCount": 1
    }
  ],
  "links": [],
  "notices": [
    {
      "code": "query.incomplete",
      "message": "More relationships may exist.",
      "hint": "Use --detail explain."
    }
  ]
}
```

YAML serializes the same data and detail-dependent fields. Complete summaries
have an empty notices array, without coverage matrices or occurrence tables.
Intentional skips receive concise notices at summary, enumerated paths at higher
detail. They do not silently disappear or become failure solely due to the skip.

### Explain and evidence

Explain retains summary results and adds structured explanations and coverage in
JSON/YAML. Human output can show:

```text
books/example.md —Book:author→ people/alice.md
  Declared at frontmatter author.
  Book applies because rule Published requires it.
  Target resolved; Person conformance failed:
    Required property "name" is missing.

Search incomplete
  Could not read private/draft.md.
  Additional relationships may exist.

Use --detail evidence for full provenance and assessment evidence.
```

Evidence stores occurrences once, with separate named interpretations referring
to them and per-file directional references. Multiple interpretations can share
an occurrence. Selecting both endpoints does not duplicate evidence. Preserve
malformed named values, exact literal key/index paths and diagnostics without an
occurrence (for example missing required properties). Decoded frontmatter ranges
must not masquerade as raw-file ranges. IDs are response-local references.

Coverage distinguishes selection, sources, candidates and interpretations, with
limitations explaining the affected dimensions. Complete candidate enumeration
can coexist with an unreadable source. Unknown applicability remains visible.

Human output uses existing `CLIStyle`/Rainbow infrastructure: headings, styled
paths, warnings/errors and subdued hints, respecting existing color controls.
JSON/YAML are uncolored. Operational progress/warnings go to stderr, while the
result remains self-contained at the chosen detail level.

## Execution and verification

Reuse rule applicability infrastructure and bounded portable evaluation. Ordinary
outgoing queries use scoped, lazily loaded evidence; ordinary incoming and bidirectional
queries use #180's verified assessment session. `--index-only`/`--indexed-only`
instead reads only the published SQLite snapshot, without raw source/definition
reads, stats, refresh, writes or fallback. This is the same contract as rule
validation, correcting the earlier refresh-known-candidates misunderstanding.
Snapshot-only graph payload reuse requires matching persisted generation/epoch;
missing body, selector or interpretation evidence is explicitly incomplete.
See [snapshot-only queries](index-only-queries.md). Complete queries exit 0, including definite broken
links and conformance failures. Incomplete queries exit 1 with available results.
Invalid invocation/configuration fails under existing CLI conventions.

No new server endpoints, graph backend, authored schema semantics or automatic
domain inference are required. Preserve existing named capabilities while ordinary
discovery excludes embeds/images, attachments, external URLs and same-document
anchors. Coordinate Markdown destination conventions with #182; wikilink rules
are already specified and must not silently become Markdown URL rules.

Verify detail parity across text/JSON/YAML, no automatic verbosity escalation,
summary notices, repeated occurrences, deterministic output, rule alternatives,
failed hints/requirements, incoming sources outside selection and direct/indexed
parity. Run native tests locally, Linux in CI; WASM remains deferred under AGENTS.md.

## Final input decisions

- Markdown destination resolution is approved: resolve relative paths from the
  source document, decode percent escapes once, and do not guess extensions.
  Leading `/` is unsupported without a publishing-root contract. Preserve
  fragments without validating renderer-specific anchors. Keep resolution confined
  to the explicit root; these rules do not change existing wikilink semantics.
- File-list contract (approved): repeatable `--files-from <file>` for LF-delimited
  entries and `--files-from0 <file>` for NUL-delimited entries. Either accepts `-`
  for stdin, consumed at most once. Strict UTF-8 only; invalid encoding fails.
  Line mode rejects CRLF with guidance. NUL mode preserves valid UTF-8 path bytes,
  including newline characters. Do not trim, unquote, expand, interpret comments
  or escapes; ignore empty entries.
- Document entries and positional paths are root-relative. List-file locations
  are working-directory-relative and may be outside the root. Reject absolute
  document paths and root escapes. Positional paths and all lists form one
  deduplicated supplied-set selector; other selectors require explicit union or
  intersection. An explicitly empty list succeeds with zero results. No selection
  arguments is an invocation error; `--select-folder .` selects the collection.
- Unreadable list files, invalid encoding and invalid/forbidden paths fail before
  query execution. Missing/unreadable selected Markdown documents instead return
  available results, an incompleteness notice and exit 1. Reject directory and
  non-Markdown entries; suggest `--select-folder` for directories. Bound bytes
  and entry counts; reject oversized inputs without truncating selection.

### Document newline support

  LF is the only supported newline format for Markdown document processing.
  CRLF and mixed-line-ending documents are unsupported; do not silently normalize
  them or claim reliable parsing. Operations promising byte preservation must
  still preserve untouched bytes. This does not claim uniform existing rejection.
  File lists are separate from Markdown document processing; document and test
  their input contract without normalizing document bytes.

`--relation` qualification is settled: require explicit `--type`.

### Deferred BOM decision (#189)

UTF-8-only does not decide BOM treatment. Existing fm-var inputs accept one BOM;
canonical frontmatter mutation envelopes reject it. The project owner deferred
the file-list choice to [#189](https://github.com/DandyLyons/md-utils/issues/189).
No acceptance/rejection choice is implied, and the earlier rejection suggestion
remains unapproved. This separate decision does not block starting #188
implementation; do not claim a finalized BOM contract until it is settled.

Exact Swift types, schema field layout, finite work budgets and serialization
mechanics are implementation choices to document and test against this contract.

## Implementation and costs

`MarkdownCollectionQueryEvaluator` owns portable selection, applicability and
evidence partitioning. `MarkdownCollectionQuerySession` supplies native snapshots,
the existing serialized JMESPath provider, and #180-certified named assessments.
`RelationshipOptions` owns input preflight and the CLI renderer owns color styling.
Ordinary Markdown extraction uses the existing MarkdownSyntax AST (including
reference links); wikilinks and list delimiters use Parsing-based infrastructure.
Code/image/HTML regions are excluded from ordinary discovery.

Outgoing execution plans a conservative source set before loading contents.
Supplied file sets bound intersections; path exclusions prune reads. Selected
sources are assessed against relevant loaded definitions, and target documents
are memoized and loaded only as recursive named assessment reaches them. Ordinary
links require destination existence, not target contents. Exact destinations use
direct confined probes; bare names lazily acquire a bounded filename namespace.
Verification rereads consumed records and checks used exact destinations or the
discovered namespace, including negative lookups. The path does not refresh or
write the index, and does not reuse whole-collection cache certificates.

Ordinary incoming/bidirectional queries retain the bounded root
snapshot and certified assessment path. Narrow selected folders do not imply
narrow incoming discovery. Content-based selectors can require broader source
reads. Explicit type queries without rule selectors do not compile unrelated
rules. Query projections and ordinary-link extraction are not persistently cached.
Document parsing for tag/JMESPath selectors is skipped when neither is requested;
rule ordering is computed once per query.

Reproduce scaling checks with `python3 scripts/benchmark-relationship-outgoing.py`.
On a local debug build, five-run median subprocess times were approximately
0.034 s with no unrelated files and 0.033 s with 1,000 unrelated 34 KiB documents
for an exact destination. Bare-name lookup increased from 0.034 s to 0.204 s,
reflecting filename discovery/verification. These synthetic results are not a
measurement of a user's vault, and timing thresholds are not unit-test assertions.

File-list inputs are limited to 8 MiB aggregate UTF-8 bytes and 100,000 entries
before deduplication. Query limits reuse `MarkdownRelationshipLimits`: 10,000
records, 64 MiB record bytes, 100,000 candidate paths, assessment nodes and
occurrences per extraction phase, 1,000 definitions and 5,000,000 selection/rule
work steps. `--max-records` and `--max-occurrences` override those CLI limits.
Oversized lists fail preflight; exhausted query budgets retain available evidence
with incomplete coverage. Indexed candidate/record exhaustion likewise returns
bounded evidence instead of silently claiming completeness.

Evidence fields are `files`, `occurrences`, `namedRelationships` and `assessments`.
`files` contains named/unnamed directional ID lists. Named interpretation
`assertion` retains declaration/target assessment evidence without duplicating
the occurrence's authored value or location, and `containedOccurrences`
connects recognized substrings of malformed whole-value assertions without
presenting them as independent unnamed assertions. Explain adds `coverage`,
`explanations`, `diagnostics` and `skipped`; summary omits all these fields.
The same Codable model drives JSON and YAML. Text evidence additionally prints
the complete, formatted evidence object after its readable explanation.

Tests: `swift test --filter 'CollectionRelationshipQueryTests|RelationshipCommandsTests|RelationshipRegressionCommandsTests|RelationshipCacheTests|MarkdownRelationshipTests|WikilinkOccurrenceTests'`.
These cover root-wide incoming discovery, selectors and compound obligations,
repeated/shared evidence, malformed hints, exact Markdown resolution, LF/NUL input,
detail/format parity, budget exhaustion and direct/indexed behavior.
