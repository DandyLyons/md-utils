# Batch operations

Commands using shared path options generally accept files and directories and
recurse by default (`--no-recursive` disables traversal). Check each command's
help: `lines`, `explore`, `extract`, and most section edits require one file;
`fm search` always recurses and has its own options. `body` and `convert to-text`
require paths or stdin rather than implicitly scanning the working directory.
`links backlinks` traversal flags select targets; its source scan always recurses.

`fm search '<JMESPath>' ./posts/` directly scans YAML frontmatter without the
SQLite index. Raw output is absolute paths, one per line; `--format json|yaml|plist`
serializes matches. TOML input/output is rejected. No matches succeed with empty
stdout (including structured formats). Query evaluation errors skip a file;
read/parse errors fail after reporting available matches. `fm array contains`
supports string membership in YAML/TOML and `--case-insensitive`; unlike search,
no matches fail. Missing/non-array keys are skipped even with `--invert`.
`fm has` prints true/false and succeeds for missing keys; never use its exit code
as a presence predicate. `fm set --value` always stores a string, not a boolean
or array. `fm dump --format raw` reserializes the source format; it does not
preserve original bytes or comments. Use `fm dump` for categorized collection
inventory. `fm list` continues through files without keys and retains failures
from earlier files.

```bash
md-utils fm set --key author --value "Jane Doe" posts/
md-utils toc docs/*.md
```
