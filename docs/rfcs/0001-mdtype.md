# RFC 0001: mdtype — Structural Types for Markdown Records

- Status: Implemented
- Definition format: `md-utils-type-schema: "1"`
- Date: 2026-08-01
- Scope: `MarkdownUtilitiesCore`, `MarkdownUtilities`, and `md-utils`

## Abstract

`mdtype` is a structural, non-exclusive type system for complete Markdown records. A named and versioned type contract can constrain three independent domains:

1. YAML frontmatter, using one or more JSON Schemas;
2. the Markdown body, using AST-backed structural predicates; and
3. record context, using facts supplied by the host, such as a collection-relative logical path.

A record conforms to a type when it can be analyzed and every requirement in the contract succeeds. Recommendations produce advisories but do not affect conformance. A record can conform to any number of types simultaneously. Type hints can nominate likely types, but never establish conformance without assessment.

This RFC specifies the mdtype v1 data model, definition format, validation and assessment semantics, diagnostic model, repair model, portable host boundary, and filesystem conventions implemented by `md-utils`.

## Status of This RFC

This document describes the implemented mdtype v1 design. The project remains in a `0.x.x` release line, so Swift APIs and CLI presentation may evolve. Changes that alter the meaning or accepted shape of an mdtype definition require a new value of `md-utils-type-schema`.

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHOULD**, **SHOULD NOT**, and **MAY** in this document are normative.

## Motivation

Markdown collections commonly encode recurring concepts such as `Book`, `Article`, `Runbook`, or `Publishable`. Those concepts are rarely described by frontmatter alone. Their identity may depend on a combination of metadata, body structure, and external collection context.

mdtype provides one contract that can express all three dimensions while preserving these properties:

- Markdown remains the canonical stored representation.
- Conformance is discovered from structure, not granted by a nominal tag.
  - A nominal tag may be used as a type hint to declare that a markdown file intends to follow a particular type. But a type hint is only a hint, and a markdown file doesn't actually conform to the type unless it's structure meets the type's requirements. 
- Invalid content remains representable and diagnosable.
- Portable assessment performs no implicit filesystem or network access.
- Requirements and recommendations remain distinct.
- Repairs are structured, reviewable, and never require the tool to invent a domain value.

## Goals

mdtype v1 is designed to:

- mdtype is a [Duck typing](https://en.wikipedia.org/wiki/Duck_typing) and [Structural typing](https://en.wikipedia.org/wiki/Structural_type_system) system, that in many ways is similar to [Typescript](https://www.typescriptlang.org/)'s type system.
- assess a complete Markdown resource rather than frontmatter in isolation;
- support overlapping types without inheritance or a single primary type;
- compose JSON Schema validation with Markdown-aware predicates;
- distinguish required conformance from advisory guidance;
- return stable, machine-readable diagnostics and repair proposals;
- allow filesystem, server, database, and in-memory hosts to use the same core evaluator; and
- make all external inputs explicit at the portable Core boundary.

## Non-Goals

mdtype v1 does not define:

- nominal type assignment;
- type inheritance, subtyping, unions, intersections, or generics;
- automatic selection of one most-specific type;
- coercion of a nonconforming record into a type;
- a network schema-fetching protocol;
- Markdown flavor validation;
- arbitrary user-authored predicates or executable validation code;
- rule applicability; or
- persistent storage or synchronization semantics.

Reusable policy rules are a separate model. A type asks whether a record has a structure. A rule first asks whether it applies and then evaluates its checks. Rules may use type conformance as an applicability condition, but rules are not mdtypes.

## Terminology

### Record

A **record** is the canonical resource supplied for assessment. It consists of:

- `content`: REQUIRED canonical Markdown text;
- `identity`: OPTIONAL stable identity;
- `revision`: OPTIONAL revision or content-hash value; and
- `context`: OPTIONAL host-supplied facts.

The record remains representable even when its frontmatter or Markdown cannot be parsed. This allows parse failures to be returned as conformance diagnostics.

### Document

A **document** is a successfully parsed content view derived from a record. It has no persistent identity, revision, logical path, or storage location of its own.

### Type definition

A **type definition** is a named, versioned structural contract serialized as YAML, JSON, or TOML.

### Requirement

A **requirement** is a constraint whose failure produces an error and prevents conformance.

### Recommendation

A **recommendation** is a constraint whose failure produces an advisory and does not prevent conformance.

### Host

A **host** is the environment that provides records, type definitions, schema resources, and persistence. The filesystem integration and CLI are hosts over the portable Core model.

## Conformance Model

Conformance is structural, non-exclusive, and conjunctive.

For record `R` and type definition `T`:

```text
conforms(R, T) := assessment(R, T) contains no error diagnostics
```

All requirements in all domains have AND semantics. All frontmatter schemas also have AND semantics. Recommendations are evaluated and reported, but excluded from the conformance decision.

No type declaration inside a record makes the record conform. Conversely, a record does not need a type hint to conform. Evaluating a registry can therefore produce zero, one, or many conforming types for one record.

Type names are stable and case-sensitive. `Book` and `book` are different names.

## Definition Discovery and Serialization

### Project layout

The native project host recursively discovers definitions under:

```text
.md-utils/types/
```

A definition filename MUST end with one of these compound extensions:

- `.mdtype.yaml`
- `.mdtype.yml`
- `.mdtype.json`
- `.mdtype.toml`

Suffix matching is case-insensitive. Other files under `.md-utils/types/` are ignored. The declared `name`, not the filename, is the type's identity.

The portable Core decoder does not perform discovery and can decode explicitly supplied YAML, JSON, or TOML from any host.

### Definition envelope

An mdtype v1 definition is an object with exactly these top-level members:

| Member | Type | Meaning |
| --- | --- | --- |
| `md-utils-type-schema` | nonempty string | Version of the definition language; MUST be `"1"` for this RFC. |
| `name` | nonempty string | Stable, case-sensitive type identity. |
| `version` | nonempty string | Version of this type contract. |
| `frontmatter` | object | Frontmatter presence and schema constraints. |
| `body` | constraint group | Markdown body requirements and recommendations. |
| `context` | constraint group | Host-context requirements and recommendations. |

Unknown top-level members are invalid. All six members are REQUIRED.

`version` is opaque. Semantic Versioning is RECOMMENDED, but an implementation MUST NOT require it. A registry contains at most one definition for a given type name; mdtype v1 does not load several versions of the same name concurrently.

### Complete example

```yaml
md-utils-type-schema: "1"
name: Book
version: "1.0.0"

frontmatter:
  presence: required
  schemas:
    - inline:
        $schema: https://json-schema.org/draft/2020-12/schema
        type: object
        required: [kind, title]
        properties:
          kind: { const: book }
          title: { type: string, minLength: 1 }
          author: { type: string }
    - ref: ../schemas/publishable.schema.json

body:
  requirements:
    - id: book-title
      heading: { text: Book, level: 1 }
    - id: synopsis
      section:
        heading: { text: Synopsis, level: 2 }
        content: nonEmpty
    - id: chapters-below-book
      headingRelationship:
        parent: { text: Book, level: 1 }
        child: { text: Chapters }
        relationship: descendant
  recommendations:
    - id: reviews
      section:
        heading: { text: Reviews, level: 2 }
        content: any

context:
  requirements:
    - id: book-path
      path: { glob: "books/**/*.md" }
  recommendations: []
```

## Definition Validation

A host MUST validate and compile the complete registry before assessing records. Registry construction fails when any of these conditions occurs:

- a definition uses an unsupported `md-utils-type-schema` value;
- two definitions have the same case-sensitive type name;
- a definition contains the same constraint ID more than once;
- an inline or referenced JSON Schema is not an object;
- a schema resource cannot be resolved;
- external schema references contain a cycle; or
- different schemas in one type contract declare the same `$id` with different content.

Constraint IDs MUST be nonempty and unique across the type's body requirements, body recommendations, context requirements, and context recommendations. Their scope is the whole type, not one constraint group. IDs are stable handles for diagnostics and selective repair.

The bundled JSON Schema at `Sources/md-utils/Resources/1_md-utils-type.schema.json` is the canonical machine-readable schema for the definition envelope.

## Frontmatter Domain

### Shape

`frontmatter` accepts exactly these members:

| Member | Required | Meaning |
| --- | --- | --- |
| `presence` | No | `required` or `optional`. |
| `schemas` | No | Array of inline or referenced JSON Schema objects. Defaults to an empty array. |

Each item in `schemas` MUST contain exactly one of:

```yaml
- inline: { type: object }
- ref: ../schemas/example.schema.json
```

An inline schema MUST be an object. A `ref` MUST be a nonempty string.

### Presence

The effective presence rule is:

| Explicit `presence` | Schema list | Effective behavior |
| --- | --- | --- |
| `required` | Any | A physical frontmatter block is required. |
| `optional` | Any | Absence is accepted and schemas are skipped. |
| omitted | Nonempty | Frontmatter is implicitly required. |
| omitted | Empty | Frontmatter presence is unconstrained. |

When frontmatter is present, every schema is evaluated even if `presence` is `optional`. An empty frontmatter mapping is schema-visible as an empty object.

### Schema-visible value

The YAML frontmatter mapping is converted to the JSON data model: null, Boolean, integer, number, string, array, or string-keyed object.

The top-level `$md-utils` member is reserved system metadata. The evaluator MUST remove the entire member before JSON Schema validation. A schema therefore cannot require, reject, or inspect `$md-utils` metadata.

Malformed YAML produces an error diagnostic and schema evaluation is skipped for that record.

### JSON Schema semantics

mdtype v1 uses JSON Schema Draft 2020-12 semantics. If a schema omits `$schema`, the registry compiler supplies the Draft 2020-12 URI.

Every listed schema validates the same schema-visible frontmatter object independently. The result is equivalent to an `allOf` across the list.

Schema resources are resolved while the registry is built, not during record assessment. The portable Core MUST obtain external resources through an explicit resource provider and MUST NOT open files or fetch URLs implicitly.

The native filesystem provider:

- resolves a top-level `ref` relative to the definition file;
- resolves nested external `$ref` values relative to the containing schema resource;
- accepts schema resources serialized as JSON or YAML objects;
- rejects absolute resource paths;
- rejects lexical or symbolic-link escapes outside the project root; and
- rejects missing resources and reference cycles.

Internal fragment references beginning with `#` remain within the current schema resource.

## Constraint Groups

`body` and `context` are constraint groups. Each group MUST contain exactly these arrays:

```yaml
requirements: []
recommendations: []
```

Every array item MUST be an object containing:

1. one nonempty `id`; and
2. exactly one predicate member.

A predicate is valid only in its declared domain. `heading`, `headingRelationship`, `section`, `maxBodyLines`, and `maxBodyWords` are body predicates. `path` is a context predicate.

## Body Domain

The body is the Markdown content after frontmatter removal. Body predicates operate on an analyzed Markdown representation unless a predicate explicitly defines raw-text counting.

### Heading matching

A heading selector has this shape:

```yaml
text: Synopsis
level: 2
```

`text` is REQUIRED and nonempty. `level` is OPTIONAL and, when present, MUST be an integer from 1 through 6.

Heading text is the rendered text extracted from the Markdown heading. Matching is exact and case-sensitive. When `level` is omitted, any heading level matches. A constraint succeeds when at least one heading matches.

### `heading`

```yaml
- id: synopsis-heading
  heading: { text: Synopsis, level: 2 }
```

The predicate succeeds when the body contains at least one matching heading.

### `headingRelationship`

```yaml
- id: synopsis-under-book
  headingRelationship:
    parent: { text: Book, level: 1 }
    child: { text: Synopsis }
    relationship: directChild
```

`relationship` MUST be either:

- `directChild`: a matching parent is the matching child's immediate heading parent; or
- `descendant`: a matching parent occurs anywhere in the child's heading ancestry.

Heading ancestry is determined by document order and heading level. The parent of a heading is the nearest preceding heading with a lower numeric level. A relationship succeeds when any matching child has a matching ancestor with the requested relationship.

### `section`

```yaml
- id: synopsis-content
  section:
    heading: { text: Synopsis, level: 2 }
    content: nonEmpty
```

`heading` is REQUIRED. `content` is OPTIONAL and defaults to `any`.

- `any` requires a matching heading, even if it has no direct content.
- `nonEmpty` requires at least one matching heading with non-whitespace direct content before the next heading.

Descendant subsections do not by themselves make their parent section's direct content nonempty.

### `maxBodyLines`

```yaml
- id: concise-lines
  maxBodyLines: 200
```

The value MUST be a nonnegative integer. The predicate succeeds when the body has no more than the specified number of LF-separated components. An empty body has zero lines. In v1, a nonempty body ending in LF includes the final empty component in its count.

### `maxBodyWords`

```yaml
- id: concise-words
  maxBodyWords: 1500
```

The value MUST be a nonnegative integer. The predicate succeeds when the raw Markdown body has no more than the specified number of whitespace-delimited tokens. Markdown punctuation and markup are not stripped before counting.

## Context Domain

Context is supplied by the host and is not derived by the portable evaluator. The record context model can carry a logical path, storage metadata, type hints, and arbitrary attributes. mdtype v1 defines one context predicate: `path`.

### Logical paths

A logical record path is collection-relative and uses `/` separators. Construction removes one leading `./` and then rejects paths that are:

- empty;
- absolute;
- directory paths ending in `/`;
- written with `\\` separators; or
- composed with empty, `.`, or `..` path segments.

The native file adapter derives this path relative to the project root and rejects records outside that root.

### `path`

```yaml
- id: book-location
  path: { glob: "books/**/*.md" }
```

`glob` MUST be a nonempty string. The pattern matches the entire logical path and is case-sensitive. The portable glob vocabulary is:

| Token | Meaning |
| --- | --- |
| `*` | Zero or more characters other than `/`. |
| `?` | Exactly one character other than `/`. |
| `**` | Zero or more characters, including `/`. |
| `**/` | Zero or more complete path segments, so `books/**/*.md` matches both `books/dune.md` and `books/classics/dune.md`. |

All other characters are literals. v1 does not define character classes, brace expansion, or escaping.

If the record has no logical path, a `path` constraint fails with `context.path.unavailable`. A missing context value is not a reason to skip a required constraint.

## Type Hints

A record MAY nominate likely types through the reserved frontmatter member:

```yaml
---
$md-utils:
  typeHints:
    - Book
    - name: Publishable
      version: "1.0.0"
title: Dune
---
```

Hosts MAY also provide hints in record context when canonical content is stored elsewhere. Duplicate hints from content and context are coalesced while preserving first occurrence order.

A hint is either a nonempty type-name string or an object with a nonempty `name` and an optional string `version`. Hints are claims, never evidence. Verification returns one of these statuses:

| Status | Meaning |
| --- | --- |
| `confirmed` | The named definition exists, the requested version is available, and full assessment conforms. |
| `rejected` | The definition and version are available, but full assessment does not conform. |
| `unknownType` | No loaded definition has the case-sensitive name. |
| `unavailableVersion` | The name exists, but its loaded contract version is not the exact requested string. |

Malformed `$md-utils.typeHints` metadata produces `type.hint.malformed`. Because malformed system metadata is an error diagnostic on the analyzed record, it prevents conformance until corrected.

## Assessment Algorithm

For each record and type, an implementation MUST perform the following conceptual steps:

1. Look up the type by exact, case-sensitive name. An explicit lookup of an unknown type fails before assessment.
2. Split frontmatter from the body and parse schema-visible YAML.
3. Parse and remove reserved `$md-utils` metadata; combine valid content hints with host hints.
4. Analyze body headings, heading ancestry, section content, line count, and word count.
5. Start the diagnostic set with record parse and system-metadata diagnostics.
6. Apply the effective frontmatter presence rule.
7. If schema evaluation is applicable, validate the user frontmatter against every compiled schema.
8. Evaluate body requirements, then body recommendations.
9. Evaluate context requirements, then context recommendations.
10. Return the definition name and version with all diagnostics.

Assessment SHOULD analyze a record only once when evaluating several definitions. Assessment MUST NOT mutate the record.

The conformance result is true exactly when no returned diagnostic has severity `error`.

## Diagnostics

Every assessment diagnostic contains:

- a stable `code`;
- severity `error` or `advisory`;
- domain `record`, `frontmatter`, `body`, `context`, or `typeHint`;
- an OPTIONAL constraint ID;
- a logical location;
- a human-readable message; and
- zero or more structured fix-its.

mdtype v1 defines these assessment codes:

| Code | Condition |
| --- | --- |
| `record.frontmatter.invalid-yaml` | Frontmatter cannot be parsed as a YAML mapping. |
| `type.hint.malformed` | Reserved type-hint metadata has an invalid shape. |
| `frontmatter.presence.required` | Required physical frontmatter is absent. |
| `frontmatter.schema.required-property` | JSON Schema reports a missing required property. |
| `frontmatter.schema.invalid` | Another JSON Schema assertion fails. |
| `frontmatter.schema.engine-error` | The schema engine cannot complete validation. |
| `body.heading.missing` | A heading predicate fails. |
| `body.heading.relationship` | A heading relationship predicate fails. |
| `body.section.missing` | A section with `content: any` is missing. |
| `body.section.empty-or-missing` | No matching section has nonempty direct content. |
| `body.lines.maximum` | `maxBodyLines` is exceeded. |
| `body.words.maximum` | `maxBodyWords` is exceeded. |
| `context.path.unavailable` | A path predicate has no logical path to evaluate. |
| `context.path.mismatch` | The logical path does not match its glob. |

A failed requirement uses severity `error`; a failed recommendation uses severity `advisory`. Parse and malformed-system-metadata failures are errors independent of a particular constraint.

Consumers MUST use `code`, `severity`, `domain`, and `constraintID` for automation rather than parsing the human-readable message.

## Fix-Its and Repair

A fix-it is a structured proposal with an ID, title, safety classification, and one or more record edits.

### Safety classes

| Safety | Meaning |
| --- | --- |
| `automatic` | Every value is determined by the contract or edit. |
| `requiresInput` | At least one domain value must be supplied explicitly. |
| `advisoryOnly` | The proposal repairs a recommendation and must not be selected by a requirements-only workflow. |

### v1 record edits

mdtype v1 can propose:

- creating an empty frontmatter block;
- setting a frontmatter value at a string-key path;
- requesting a frontmatter value at a string-key path; and
- appending a heading with known text and level.

For a missing JSON Schema required property:

- a property-level `const` supplies a deterministic automatic value;
- a property-level `default` is only a suggestion and remains `requiresInput`; and
- otherwise the fix requests explicit input.

An implementation MUST NOT treat a JSON Schema `default` as an automatic value. It MUST NOT invent an unknown value.

A missing heading can be appended automatically. When the predicate omits a level, the v1 repair defaults the appended heading to level 2. A nonempty-section failure and a relationship failure have no automatic v1 repair.

Repair is an explicit second phase. The portable fixer applies only selected fix-its to an in-memory record. The host owns prompting and persistence. After applying edits, the host MUST reassess the updated record before claiming conformance.

The native CLI previews candidates, excludes recommendations unless requested, can filter by stable constraint ID, and writes accepted changes atomically. Noninteractive `--yes` mode applies deterministic edits but skips an input-required edit unless all requested values were supplied explicitly.

## Portability and Host Responsibilities

The architecture separates pure assessment from host integration:

| Layer | Responsibilities |
| --- | --- |
| `MarkdownUtilitiesCore` | Record and type models, decoding, registry validation, schema-graph compilation, Markdown analysis, predicate evaluation, diagnostics, hint verification, and in-memory repair. |
| `MarkdownUtilities` | Recursive definition discovery, project-confined schema loading, logical filesystem paths, record reading, and atomic record writes. |
| `md-utils` | Command parsing, path selection, prompts, rendering, exit status, and user-approved persistence. |

Portable APIs MUST receive all external resources and context explicitly. They MUST NOT scan directories, read files, access a database, fetch a URL, prompt a user, or write persistent state during assessment.

Hosts SHOULD resolve and compile a registry once, then reuse its immutable definitions and schemas across record assessments.

## Security Considerations

Schema resources can contain transitive references. Native hosts MUST confine resource resolution to the configured project root after both path normalization and symbolic-link resolution. Absolute references and root escapes MUST be rejected.

Type definitions and schemas are data, not executable code. Implementations MUST NOT evaluate embedded scripts or predicates.

Automatic repair changes canonical content. Hosts SHOULD preview changes, preserve unrelated content where possible, write atomically, and reassess before reporting success. Input-required fixes MUST remain under explicit user or caller control.

## Versioning and Compatibility

`md-utils-type-schema` versions the definition language. It is independent of a type contract's `version` member.

- A v1 implementation MUST reject an unknown definition-language version.
- A host MUST treat type contract versions as opaque strings and compare requested hint versions exactly.
- Adding a new predicate or changing predicate semantics requires a definition-language compatibility decision and ordinarily a new schema version.
- Changing CLI text, output styling, or native discovery internals does not by itself require a new definition-language version when serialized definitions and conformance semantics remain compatible.

## Rationale

### Why structural and non-exclusive?

Markdown concepts overlap naturally. A record can be both a `Book` and `Publishable`, and the useful question is whether it satisfies each contract—not which single label owns it.

### Why three domains?

Frontmatter, body structure, and host context have different data models and portability concerns. Keeping them explicit prevents filesystem facts from leaking into content schemas and keeps body checks Markdown-aware.

### Why JSON Schema for frontmatter?

JSON Schema supplies a mature vocabulary for typed object validation, constants, arrays, nested values, and composition. mdtype adds only the Markdown- and host-specific domains that JSON Schema cannot observe.

### Why are hints non-authoritative?

Treating a tag as proof would make the system nominal and allow stale metadata to override the record's actual shape. Verification preserves hints as useful indexing information without weakening conformance.

### Why are rules separate?

Applicability and conformance answer different questions. Keeping them separate avoids turning file-selection policy into an implicit type hierarchy.

## Reference Commands

The implemented CLI surface is:

```bash
md-utils types add Book --version 1.0.0
md-utils types list
md-utils types describe Book
md-utils types doctor
md-utils types check Book books/
md-utils types verify books/
md-utils types identify books/dune.md
md-utils types find Book books/
md-utils types fix Book books/dune.md --dry-run
md-utils types schema
```

`types schema` emits the machine-readable schema for `md-utils-type-schema: "1"`. CLI commands are an implementation surface over this RFC; they are not required of other hosts.

## Future Work

Potential later RFCs may define additional predicates, reusable constraint composition, richer context attributes, explicit type relationships, schema publication conventions, or an interchange format for assessments. Such features are not implied by mdtype v1 and must not be inferred by current implementations.
