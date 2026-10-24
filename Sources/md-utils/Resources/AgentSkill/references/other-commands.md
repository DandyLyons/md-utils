# Configuration and additional commands

## Configuration

`config info` reports CLI/config information; `config schema` prints the default
project schema. `config init --root ./project/` creates project configuration and
empty resource directories, defaulting to config 0.2.0. It does not create types
or rules. Use [rules.md](rules.md) for version-specific editing and migration;
do not substitute a schema URL for a runtime version discriminator.

## Formatting

```bash
# Preview normalized bullets and aligned tables; --in-place opts into writing.
md-utils format --bullets-dashes --normalize-tables document.md
```

`--bullets-dashes` and `--bullets-asterisks` are mutually exclusive, as are
`--italic-asterisks` and `--italic-underscores`. `--normalize-tables` aligns cells;
`--max-width` caps padding (default 80), never truncates content. Output goes to
stdout unless `--in-place` is supplied. Directory inputs follow shared batch options.

## Metadata and slugs

`meta read document.md` reads OS file attributes and extended attributes, not
frontmatter. Directory traversal is recursive by default. Inspect `meta read
--help` for platform/output options rather than interpreting absent platform
attributes as document metadata.

`slug 'My Title'` prints a candidate without changing files or checking uniqueness.
`--policy unicode|strictASCII|preserve` chooses generation policy. Slug generation
does not allocate an identity or replace heading-anchor semantics.

## Experimental OKF

`okf` targets the Open Knowledge Format v0.1 draft and may change. Its subcommands
are `init`, `validate`, `report`, `doctor`, and `type`; inspect the selected
subcommand's help for arguments. Initialization writes a bundle; report/doctor
separate conformance from advisory health findings. Do not guess a concept's
`type`: use only a user-supplied value. Do not strengthen draft requirements into
mandatory checks or describe OKF as mdstandard support.

OKF specification evolution and exhaustive domain authoring are outside this
skill's contract. Use the installed CLI's supported draft and the user's explicit
domain model. Standards remain [upcoming](standards.md).
