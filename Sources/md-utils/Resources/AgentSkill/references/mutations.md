# Durable drafts and managed transfers

## Configure writable intent

Drafts use version 3 server configuration at `.md-utils/server/server.yaml` without
needing an HTTP process. A resource must select the source, expose fields/body
through `writable.codec`, and enable `patch` or `replace` in `mutations.operations`.
Use `--server-config` for an alternative file and `--project-root ./` for the project.
For example, assuming a rule named notes:

```yaml
serverConfigVersion: "3"
resources:
  - name: notes
    route: /notes
    operations: [list, get]
    selection: {mode: rule, rule: notes}
    identityPolicy: {source: logicalPath}
    writable:
      codec: {frontmatterFields: [title], bodyWritable: true}
    mutations: {operations: [patch, replace]}
```

Save `{"frontmatter":{"set":{"title":"New"}}}` as `edit.json`. Null in `set`
stores null; `remove: ["title"]` deletes a field; omission preserves a field.
Only writable fields are allowed. Replacement supplies the complete writable
representation and any required body. Input is bounded to 8 MiB. Get raw source
SHA-256 with `index query 'SELECT path,hash FROM files' --format jsonl`; retain the
revision reviewed when authoring the edit, rather than silently refreshing it.

## Stage, preview, and apply

Current limitation: general draft validation can report
`relationship.context.unavailable` when named-relationship types are loaded, even
for an unrelated title edit. See [#199](https://github.com/DandyLyons/md-utils/issues/199).
Treat this as unavailable validation: do not remove contracts or bypass preservation
to force the edit. Relationship Fix-Its have their separate reviewed workflow in
[rules.md](rules.md).

Stage explicit patch/replace intent with `index draft add <collection-relative-path>
--resource <name> --revision <source-sha256> --patch-file <file>` (or `--replace-file`).
Use the configured resource's shared mutation JSON envelope and operation opt-ins.
`index draft list/show` reads durable intent; `index apply --dry-run` previews exact
source and diagnostics without refresh, recovery, or persistent state changes.
`index apply` replans and revision-checks each file, publishing all affected scopes
and enabled FTS. Drafts remain outside SQLite through refresh/rebuild. Managed move
evidence can follow a configured UUID; external relocation, UUID collisions, and
stale hashes require explicit review. Never treat arbitrary indexed-row edits as
write intent. Partial batches retain completed/pending outcomes; use `index draft
resolve <id> --decision confirmCommitted|confirmNotCommitted` only after reviewing
the receipt and actual source. Unresolved submitted drafts cannot be discarded.

Use managed `copy`/`move` for UUID-aware transfers rather than naive filesystem
copies. Both require `--resource`, `--revision <source-sha256>`, and
`--idempotency-key`; the source is collection-relative and the destination argument
is a filename inside the resource's configured `creation.directory`. The server
resource must explicitly enable the operation. Copy accepts `--identifiers` JSON
for new configured identifiers (for example a slug), generates a new configured
UUID and preserves the source. Move preserves bytes/UUIDs. Neither rewrites links.
UUID allocation requires a configured persistent identity path; otherwise copy
invents no UUID field. Destinations must exist as directories; destination files
are never overwritten. Transfers stay within one collection/filesystem. Move
preserves modification time and POSIX permissions, not a promise of xattrs/ACLs.
Retain the exact revision/key for retries. Incomplete receipts require recovery;
an interrupted move can leave both paths present. Do not delete either blindly.
See [indexing.md](indexing.md) for cache lifecycle and [rules.md](rules.md) for reviewed relationship Fix-Its.
