# ``MarkdownUtilitiesIndex``

Maintain a rebuildable SQLite cache of file collections and selection assessments.

## Overview

Files remain authoritative. The native index tracks root-relative file paths,
parsed metadata and independent scope memberships. Optional FTS mode also retains
one source body per selected document. GRDB uses the operating system's SQLite
runtime, with mandatory JSON/expression-index probes and an FTS5 probe only for
FTS-mode caches. The host supplies its existing content extractor and type or rule
evaluator.

## Topics

### Updating Collections

- <doc:RefreshingCollections>
- ``CollectionIndexer``
- ``IndexScope``
- ``IndexUpdateReport``
- ``IndexRefreshLimits``

### Supplying Evaluations

- ``IndexEvaluation``
- ``IndexAssessment``
- ``IndexDiagnostic``
- ``IndexFingerprint``

### Opening the Cache

- ``SQLiteIndexDatabase``
- ``SQLiteIndexError``
- ``IndexStoragePolicy``
- ``IndexBodyMode``
- ``IndexMetadataEncoding``
- ``IndexQueryLimits``
- ``IndexQuerySummary``
