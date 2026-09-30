# ``MarkdownUtilitiesServerNative``

Read and mutate authoritative native Markdown files through shared indexed resources.

## Overview

``IndexedMarkdownRepository`` adapts configured resources to bounded indexed reads
and coordinated mutations. ``MarkdownDraftService`` stages explicit source edits
independently of the disposable cache and uses the same source codecs, assessments,
policies, collection constraints, and native persistence without an HTTP process.

Draft preview is read-only. Apply coordinates with refresh and watch through the
collection writer lease and preserves durable receipts when source has committed
but publication remains incomplete. UUIDs, source revisions, and partial provenance
have separate roles; an external disappearance never proves a managed move.

## Topics

### Applying Pending Edits

- <doc:ApplyingPendingEdits>
- ``MarkdownDraftService``
- ``MarkdownDraft``
- ``MarkdownDraftReport``

### Indexed Native Resources

- ``IndexedMarkdownRepository``
