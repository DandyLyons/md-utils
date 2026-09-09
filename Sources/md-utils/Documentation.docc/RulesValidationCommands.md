# Rules Validation Commands

Validate files against project-level rules.

## Overview

The `rules` command group manages `.md-utils/` project configuration and validates files. Configuration is read from the current working directory; `md-utils` does not search parent directories for a project root.

Use `md-utils config init` to create the project configuration along with empty `.md-utils/schemas/`, `.md-utils/types/`, and `.md-utils/rules/` directories. Initialization does not add a rule or type. Legacy configurations continue loading embedded rules; creating the directory does not opt a project into the proposed standalone format.

Rules match files by project-relative glob patterns, optional file metadata conditions, optional frontmatter conditions, optional whole-frontmatter queries, and optional document conditions. Files can match more than one rule, in which case every matching check applies.

Version `0.2.0` configs use a `rules` array. Version `0.1.0` configs using `schemaRules` still load as legacy configs. Both versions normalize through `MarkdownUtilitiesCore` into one compiled registry before files are scanned; unknown versions or fields fail without being discarded.

## Opt-in 0.3.0

Use `{"configVersion":"0.3.0"}` project settings and individual `.mdrule.json` files under `.md-utils/rules/`, recursively excluding `rules/legacy/`. Each rule has `name`, optional `match`, and required `types`. For example, `{"name":"books","match":{"paths":["Books/**"]},"types":"book.mdtype.json"}` requires the existing `.md-utils/types/book.mdtype.json` contract after selection. Selected invalid files fail rather than disappear.

Both expressions support recursive `allOf`, `anyOf`, `oneOf`, and `not`. Group arrays are nonempty, and a group cannot mix operators or leaf fields. Evaluation errors are distinct from nonconformance and cannot be inverted into success. Explanations retain branch evidence. Type references require explicit filenames relative to `types/`; nested filenames are supported. Schemas remain definition-relative resources, and `schemas/` is optional. Valid `$md-utils.typeHints` still refer to declared type names, not filenames.

`rules add books --type book.mdtype.json` creates a standalone rule. List, describe, validate, matching, and removal use individual files. Removal preserves types and schemas; `--delete-schema` is unavailable in 0.3.0. Initialization still defaults to 0.2.0.

Back up `.md-utils/`, then run `config migrate --to 0.3.0 --dry-run` before applying. Automatic conversion currently supports required-schema-only rules. Unsupported checks, unsafe resources, and collisions fail before writes. Original config bytes and legacy rule payloads are retained; active config is replaced last. No staging or manifest is used, and multi-file atomicity is not promised. Interrupted writes report completed files: restore the backup or inspect artifacts before retrying. Migrated rules may newly reject malformed type hints and use different diagnostics; other pass/fail/skipped changes are not permitted. See the repository's `docs/config-v0.3.md` for full examples and recovery details.

```bash
md-utils config init
md-utils rules add books --path "Books/**/*.md" --tag Book
md-utils rules validate
md-utils rules validate books
md-utils rules list
md-utils rules describe books
```

## Non-Markdown Files

Project scans are Markdown-only by default, even when configured paths match other
extensions. Add `--include-non-md` to `rules validate` or `rules files-matching`
to include non-Markdown files selected by those paths. `rules matching` opts an
explicit non-Markdown file in automatically, except `.txt`, which requires the
flag to match `fm` selection behavior.

Mapped extensions reuse the shipped wrapped-frontmatter syntaxes:

- `c-block`: C-family languages, Swift, Java/Kotlin, JavaScript/TypeScript, Go, Rust, Dart, PHP, CSS-family files, SQL, and JSONC
- `html-comment`: HTML, XML, SVG, Vue, and Svelte
- `python-docstring`: Python and Python interface files
- `powershell-block`: PowerShell files
- `lua-block`: Lua files
- `line-comment`: shipped exact basenames and shell, Ruby, R, YAML/TOML,
  Make/CMake, properties, Nix, Bazel, and Terraform extensions
- `markdown-text`: `.txt`, only with `--include-non-md`

Wrapped or line-comment YAML/TOML supports frontmatter field predicates, JMESPath, `$md-utils` type
hints, and JSON Schema validation. Raw body predicates and counts operate on the
host source after the recognized envelope is removed; they can therefore match comments or
string literals. Markdown headings, sections, heading relationships, required
headings, and wikilinks are unsupported for non-Markdown files.

Rules resolve the complete filename so exact basenames such as
`requirements.txt` and `.env.schema` win over `.txt` or suffix behavior. They use
shipped mappings only; `fm --line-comment-frontmatter` is intentionally not a
rules configuration mechanism. Recognized malformed hash-comment blocks are
excluded from raw-body predicates and produce stable structural diagnostics.

Opted-in unmapped extensions can use file and raw-body predicates. A rule that
requires frontmatter for one of those files reports that no syntax mapping exists.

## Supported Checks

The following are the serialized 0.2.0 checks. Core additionally supports programmatic
`typeConformance` checks, which enforce a type after selection and retain its original
diagnostics and fix-its. This capability is not accepted by the legacy config schemas;
0.3.0 instead uses the `types` expression described above.

- `frontmatterSchema`: validates parsed YAML or TOML frontmatter against a JSON Schema file.
- `requiredHeading`: requires an exact Markdown heading text in a Markdown body.
- `maxBodyLines`: limits Markdown body line count.
- `maxBodyWords`: limits Markdown body word count.

## Frontmatter Predicates

Field predicates under `rules[].match.frontmatter` are all-of predicates for one frontmatter key. Multiple operators on one key are implicit AND.

Supported operators are `equals`, `doesntEqual`, `includes`, `notIncludes`, `hasKey`, `doesntHaveKey`, `regex`, `startsWith`, `endsWith`, `contains`, `empty`, `emptyString`, `emptyArray`, `emptyObject`, `notEmpty`, `in`, `notIn`, `greaterThan`, `greaterThanOrEqual`, `lessThan`, `lessThanOrEqual`, `after`, `onOrAfter`, `before`, `onOrBefore`, inclusive `between`, and `typeIs`.

Missing keys are distinct from value inequality. A missing key does not match `doesntEqual`, `notIncludes`, or `notIn`. Only `doesntHaveKey` intentionally matches a missing key.

`contains` is string containment. `includes` is array membership.

Date/time predicates support date-only `YYYY-MM-DD` operands and RFC 3339 date-time operands with `Z` or numeric offsets, such as `2020-01-01T12:00:00Z` and `2020-01-01T07:00:00-05:00`. Date-only operands compare at date precision. Date-time operands compare at date-time precision. A value with more precision can match a less precise rule; a value with less precision does not match a more precise rule.

Whole-frontmatter predicates live under `rules[].match.frontmatterQuery`. Version `0.2.0` supports `jmespath`, evaluated by the CLI's serialized capability provider with truthiness defined by Core. The JMESPath dependency is intentionally not linked into portable Core or server targets.

Recursive `allOf`, `anyOf`, `oneOf`, and `not` groups are available only in config 0.3.0.

## Document Predicates

Supported document matcher operators are `hasHeading`, `headingRegex`, `hasHeadingAtLevel`, `hasSection`, `bodyContains`, `bodyRegex`, `hasWikilink`, `lineCount`, and `wordCount`. Only the raw-text and count operators apply to non-Markdown files.

`hasBrokenWikilink` is deferred until resolver context and performance behavior are designed.

## File Predicates

Supported file metadata matcher operators are `pathRegex`, `filenameEquals`, `extensionIn`, `modifiedAfter`, and `modifiedBefore`. File predicates are evaluated before file contents are parsed.

`pathRegex`, `headingRegex`, `bodyRegex`, and frontmatter `regex` use Swift `NSRegularExpression` syntax.

## Failure Behavior

Invalid YAML or TOML frontmatter is reported as an error for matched rules because frontmatter predicates and schema checks cannot proceed. Files without required frontmatter fail when the matched `frontmatterSchema` check requires frontmatter, and are skipped for optional frontmatter schema checks.
