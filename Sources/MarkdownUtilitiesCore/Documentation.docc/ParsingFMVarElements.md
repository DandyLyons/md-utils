# Parsing Frontmatter Reference Elements

Scan `<fm-var>`, `<fm-list>`, and `<fm-format>` without normalizing unrelated Markdown bytes.

## Overview

``FMVarParser`` is a swift-parsing parser whose input is `Substring` and whose output is an
``FMVarParseResult`` tied to the exact input snapshot. It returns recognized ``FMVarElement``
values in UTF-8 source order, preserves authored attributes through ``FMVarRawAttribute``, and
provides normalized ``FMVarDeclaration`` values when attribute syntax is valid.

The parser does not load `src` resources, traverse `key` paths, coerce YAML values, format values,
or decide cache freshness. Those stages can use the lossless ranges and normalized declarations
without reparsing or re-rendering the Markdown document.

```swift
let source = "Before <fm-var key=\"title\">Old</fm-var> after"
let result = try FMVarParser().parse(source)
let element = result.elements[0]

let openingTag = try result.text(in: element.openingTagRange)
let updated = try result.replacingCache(ofElementOrdinal: 0, with: "New")
```

`openingTag` is the exact authored opening tag. `updated` changes only the bytes between the
opening and closing tags; whitespace and every other source byte remain unchanged.

## Accepted Markdown Contexts

Scalar `<fm-var>` elements and inline `<fm-list>` formats (`conjunction`, `disjunction`, and `unit`)
may appear in ordinary inline Markdown, including headings, emphasis, and table cells.

Ordered and unordered `<fm-list>` elements are block content. Their opening and closing custom tags
must each stand on their own line. Their cache must contain one matching explicit HTML `<ol>` or
`<ul>` whose children are escaped `<li>` text values.

`<fm-format>` is configuration rather than rendered content. Each declaration must be top-level,
appear after YAML frontmatter and before ordinary document content, and use an explicit closing
tag. Multiple declarations may occupy this leading configuration region with whitespace between
them.

The parser does not recognize tag-like source in these literal contexts:

- fenced or indented Markdown code;
- inline code spans;
- HTML `<code>` or `<pre>` containers;
- HTML comments; and
- Markdown backslash-escaped element examples.

## Attributes and Children

Attributes remain in authored order. Their raw spelling, whitespace around `=`, quote style, raw
value, and name/value ranges are available on ``FMVarRawAttribute``. Normalized declarations decode
XML predefined and numeric character references without changing the raw attribute model.

Every fm-var family element requires an explicit closing tag. Scalar and inline-list caches accept
only the literal-text serialization defined by RFC 001 Rev 2. Block-list caches accept only their
required HTML list structure, and `<fm-format>` accepts no non-whitespace children.

## Recovery and Diagnostics

Malformed opening tags remain visible as incomplete ``FMVarElement`` values. Their
``FMVarElement/closingTagRange`` and ``FMVarElement/cacheRange`` values are `nil`, which prevents a
later synchronization stage from creating an unsafe edit. Scanning resumes at the next recoverable
candidate, so a later valid element still receives the next deterministic ordinal.

Nested, overlapping, mismatched, self-closing, and unexpected closing tags produce stable
``FMVarDiagnosticCode`` values. Duplicate and unknown attributes, invalid content models, and
placement failures also produce precise UTF-8 ranges. Diagnostics are returned in deterministic
source order; consumers should branch on their code and severity rather than human-readable text.

The direct parser entry points use typed throws and can emit only ``FMVarSourceLocationError``.
Malformed fm-var markup is recoverable source input and therefore appears in `diagnostics` rather
than being thrown. A thrown source-location error indicates that the parser could not preserve its
own snapshot-range invariants.

## Snapshot Safety

Every ``FMVarSourceRange`` belongs to the immutable ``FMVarParseResult/source`` snapshot.
``FMVarParseResult/text(in:)`` verifies both offsets and line/column coordinates before reading.
Snapshot reads and cache replacement use typed throws with ``FMVarParseResultError``, keeping
caller recovery exhaustive and separate from parse-time source-coordinate failures.
Native file-writing layers must additionally verify that the on-disk revision still matches the
parsed snapshot before applying cache edits atomically.
