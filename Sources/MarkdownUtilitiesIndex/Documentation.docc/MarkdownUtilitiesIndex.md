# ``MarkdownUtilitiesIndex``

Maintain a rebuildable SQLite cache of file collections and selection assessments.

## Overview

Files remain authoritative. The native index tracks root-relative file paths,
parsed metadata, source bodies, and independent scope memberships. GRDB uses the
operating system's SQLite runtime, with mandatory JSON and FTS5 capability probes.
The host supplies its existing content extractor and type or rule evaluator.

## Topics

### Updating Collections

- <doc:RefreshingCollections>
- ``CollectionIndexer``
- ``IndexScope``
- ``IndexUpdateReport``

### Supplying Evaluations

- ``IndexEvaluation``
- ``IndexAssessment``
- ``IndexDiagnostic``
- ``IndexFingerprint``

### Opening the Cache

- ``SQLiteIndexDatabase``
- ``SQLiteIndexError``
