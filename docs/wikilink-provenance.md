# Wikilink occurrence provenance

Core exposes `MarkdownDocument.wikilinkOccurrences(context:)` and throwing
`MarkdownRecord.wikilinkOccurrences(context:)`. Both discover embedded valid links
in YAML/TOML string values and the body without filesystem or network access.
The record API retains the supplied record snapshot, including identity, revision,
logical path and host context. A document has no record identity; its occurrences
have `source == nil`. Invalid frontmatter makes the record API throw.

```swift
let record = MarkdownRecord(
  identity: .init(rawValue: "person-a"),
  content: "---\nrelated: ['[[Person B]]', '[[Person B]]']\n---\n[[Other]]",
  revision: .init(rawValue: "host-revision"),
)
let occurrences = try record.wikilinkOccurrences(context: .standard)
// First origin: .frontMatter(path: [.key("related"), .index(0)])
// Second origin: .frontMatter(path: [.key("related"), .index(1)])
// Third origin: .body
```

Property components are literal keys or zero-based array indices. A key named
`related[0]` is `.key("related[0]")`, distinct from the array path above. Every
array index and nested object key is retained. Repeated references remain separate
occurrences. Frontmatter precedes body; traversal follows decoded mapping order,
array order, and link order within each string. Raw YAML/TOML mapping source order
is not guaranteed by this API.

Each occurrence contains the parsed `link`, parsing `context`, complete scanned
`text`, and a zero-based, half-open `utf8Range` **within that text**. For frontmatter,
text means the decoded scalar, including YAML folding or YAML/TOML escape decoding.
These offsets must never be used as raw-file byte offsets. `sourceUTF8Range` is
absent for frontmatter. Use the property path to locate the value, verify the
source revision and scalar, replace within the decoded value, and serialize using
the existing frontmatter codecs and mutation infrastructure. Formatting and comments
are subject to those codecs' existing preservation guarantees.

For body occurrences, `utf8Range` starts at byte zero of the body. Record extraction
also supplies `sourceUTF8Range` in the exact `source.content` snapshot, including
the frontmatter envelope offset. Document extraction cannot supply that range.
Ranges include brackets and any embed prefix. Hosts must check revisions before
applying edits; extraction itself neither writes nor authorizes a mutation.

`WikilinkScanner.scanOccurrences(_:context:)` supplies parsed links and UTF-8 ranges
for any supplied string. Existing `scan`, `wikilinks`, `frontMatterWikilinks`, and
`bodyWikilinks` APIs remain supported. Scanner defaults remain `.standard`;
document/record discovery defaults remain `.legacy`. Explicit `.markdownTable`
selects table escaping rules without automatically detecting table cells.

Discovery skips malformed candidates and nonstrings, scans prose for multiple
links, and does not exclude code regions. It does not establish a whole-value
Wikilink scalar, a named relationship, resolution, or relationship validity.
Declared relationship evaluation must separately retain invalid selected values;
these scanner results are not a substitute for that evaluation.

## CLI behavior

Existing `md-utils links list`, `links check`, and `links backlinks` retain their
current output contracts; they do not expose these structured occurrence results.
`links convert` continues to use its existing preview and revision-checked mutation
workflow. Its display locations are not raw source byte ranges. Library consumers
needing precise provenance should use the Core occurrence APIs above. No definition
format version or default scalar/relationship semantics changes with this addition.
