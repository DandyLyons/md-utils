# Managed copy and move

Use managed operations when duplicating or relocating records in a configured
collection. They share the mutation coordinator between REST and CLI. Resource
mutation `operations` must explicitly include `copy` and/or `move`; `creation.directory`
sets the destination directory. A creation template is not required for transfers.
The source must belong to the resource, and the destination must pass its contract
and preserve previously passing loaded contracts. Sources are revision-checked;
destinations never overwrite existing files, even with allocation `collision: suffix`.

Copy preserves the source and body bytes. It generates a fresh UUID at the configured
persistent-identity path. Without a configured UUID path it invents no field. Other
unique identifiers are preserved unless replaced through the explicitly configured
`creation.identifiers` input; a conflicting identifier fails validation. Metadata
changes can reserialize frontmatter, with the same preservation limits as other
mutations. Copy does not rerender templates or regenerate slugs implicitly.

Move (including rename) preserves content bytes, UUID, modification time, and POSIX
permissions while reassessing path-dependent identities, memberships, and rules.
The initial implementation requires one collection and one filesystem. Destination
directories must already exist. Neither operation rewrites links or references;
path-based references may need manual updates. Extended attributes/ACLs and inode
identity are not promised by this portable adapter.

## REST

`POST /books/{id}/copy` accepts:

```json
{"filename":"Dune copy.md","identifiers":{"slug":"dune-copy"}}
```

`POST /books/{id}/move` accepts:

```json
{"filename":"Dune renamed.md"}
```

Both require `MD-Utils-If-Revision` and `Idempotency-Key`. Copy succeeds with 201;
move with 200. Named lookup aliases and exact resource-scoped path routes use the
same contracts, including `/books/_mutations/copy/by-path?path=books%2FDune.md`.
The request key binds payload, source selector, lookup, and expected source revision.
An exact retry returns the original receipt even after a move removed the old path.
Generated OpenAPI describes enabled routes, request bodies, preconditions and receipts.

## CLI

The CLI loads the same server resource configuration and operation opt-ins:

```sh
md-utils copy books/Dune.md 'Dune copy.md' --resource books \
  --project-root ./ --revision "$source_sha256" --idempotency-key copy-dune \
  --identifiers '{"slug":"dune-copy"}'

md-utils move 'books/Dune copy.md' 'Dune renamed.md' --resource books \
  --project-root ./ --revision "$copy_sha256" --idempotency-key move-dune
```

`--revision` takes the canonical raw source SHA-256 (not the HTTP `r1.` encoding).
Retrieve current paths and hashes with
`md-utils index query 'SELECT path,hash FROM files' --format jsonl`.
Keep the same revision and key for retries. Commands print the durable receipt and
exit unsuccessfully when recovery/publication remains incomplete. `--server-config`
selects an alternate server configuration. `index provenance` explains retained
observations and managed relationships without changing files.

## Interrupted moves

Move is a recoverable two-path operation, not a claimed filesystem/SQLite transaction.
The coordinator durably records intent, atomically creates a no-clobber destination,
durably confirms that destination, then revision-checks and removes the source.
An interruption can leave both files present. The receipt reserves both paths against
participating writers until recovery; external editors do not honor the writer lease.

Restart recovery finishes a durably confirmed move only if the destination still
matches and the source is absent or matches its original revision. Changed sources
are never deleted, and changed destinations never justify deleting the source.
Unconfirmed crash windows require explicit operator resolution through the existing
operation recovery interface. `confirmCommitted` verifies the destination and may
finish removal of an unchanged move source. `confirmNotCommitted` requires an absent
destination and unchanged source; it does not roll files back. External editors can
still race final checks, as with the existing native mutation contract.

Confirmed copy/move events link both paths and revisions in disposable provenance.
Operator-confirmed events retain their weaker origin. A rebuilt index does not
replay old receipts into a new provenance epoch. Receipts and pending recovery remain
independent of disposable index contents.
