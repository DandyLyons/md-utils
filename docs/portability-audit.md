# MarkdownUtilities Portability Audit

**Last updated:** 2026-07-18

## Target Boundary

`MarkdownUtilitiesCore` contains content-only Markdown behavior and supports Apple platforms and Linux. It does not depend on PathKit, ArgumentParser, Rainbow, process APIs, filesystem scanning, file metadata, or extended attributes.

`MarkdownUtilities` depends on Core without re-exporting it. It owns APIs whose behavior depends on native paths, the current working directory, filesystem contents, or host metadata. Consumers import each module explicitly. `md-utils` remains responsible for command parsing, presentation, filesystem orchestration, and exit behavior.

## Source Inventory

| Classification | Source files | Reason |
|---|---|---|
| Portable Core | `MarkdownDocument.swift`; every Swift file under `Explore/`, `Formatting/`, `FrontMatter/`, `HeadingAdjustment/`, `Helpers/`, `SectionExtraction/`, `SectionReordering/`, and `TOC/` | Operates on strings, YAML nodes, or Markdown AST models without discovering host state. |
| Portable Core | `FormatConversion/Protocols/`; `FormatConversion/Shared/`; `FormatConversion/PlainText/`; `FormatConversion/MarkdownDocument+FormatConversion.swift` | Pure conversion contracts and Markdown-to-text transformations. |
| Portable Core | `Wikilink/Wikilink.swift`, `WikilinkAnchor.swift`, `WikilinkParser.swift`, `WikilinkScanner.swift`, and `MarkdownDocument+Wikilink.swift` | Parses supplied content without resolving against a filesystem. |
| Native integration | Every Swift file under `FileMetadata/` | Reads filesystem attributes and, on Darwin, extended attributes. |
| Native integration | `FormatConversion/CSV/CSVConverter.swift` and `CSVOptions.swift` | Absolute and relative metadata columns currently use PathKit and implicit current-working-directory context. |
| Native integration | `Wikilink/WikilinkResolver.swift` and `ResolvedWikilink.swift` | Scans directories and exposes PathKit paths in the public API. |
| CLI only | Every Swift file under `Sources/md-utils/` | Owns ArgumentParser commands, terminal formatting, file orchestration, and process exit behavior. |

Directory paths in the table are relative to `Sources/MarkdownUtilitiesCore/`, `Sources/MarkdownUtilities/`, or the explicitly named `Sources/md-utils/` directory.

## Dependency Assessment

| Dependency | Layer | Linux status | WebAssembly status |
|---|---|---|---|
| Swift standard library and Foundation | Core | Verified by the Linux container build and Core tests. | Requires a Swift WebAssembly SDK compilation spike. |
| MarkdownSyntax and swift-cmark | Core | Verified by the Linux container build and Core tests. | The C-backed swift-cmark dependency is unverified and is a potential blocker. |
| swift-parsing | Core | Verified by the Linux container build and parser tests. | Unverified with this package's selected version and SDK. |
| Yams and libYAML | Core | Verified by the Linux container build and frontmatter tests. | The C-backed libYAML dependency is unverified and is a potential blocker. |
| PathKit | Native only | Supported by the native package; excluded from Core. | Out of scope because it is not a Core dependency. |
| ArgumentParser, JSONSchema, JMESPath, Rainbow | CLI only | Outside the Core boundary. | Out of scope because the CLI is not a WebAssembly target. |

Linux verification uses Swift 6.2 in `Dockerfile.core-linux`. A successful image build runs `swift build --target MarkdownUtilitiesCore`, then runs the isolated `IntegrationTests/LinuxCoreSmoke/` executable against Core. The full focused `MarkdownUtilitiesCoreTests` target remains part of `swift test`; SwiftPM test filtering cannot avoid compiling unrelated package test targets.

## Placement Rules

- Put APIs in Core when all inputs are supplied explicitly and behavior depends only on those inputs.
- Put directory scanning, path discovery, file metadata, extended attributes, environment access, and host configuration in `MarkdownUtilities`.
- Put argument parsing, terminal styling, printing, and exit codes in `md-utils`.
- Do not use conditional compilation to hide an integration inside Core; introduce a native adapter instead.
- Re-run the Linux container whenever Core sources or direct dependencies change.

## Import Migration

Portable types formerly declared by `MarkdownUtilities`, including `MarkdownDocument`, now belong to the `MarkdownUtilitiesCore` module. Source files using those APIs must import Core explicitly. Files that combine portable document operations with native resolvers, CSV path metadata, or file metadata import both modules.

## Remaining WebAssembly Work

Linux support does not establish WebAssembly support. Issue 76 must install a Swift WebAssembly SDK, compile Core for the selected WASI target, test MarkdownSyntax/swift-cmark and Yams/libYAML, and replace or isolate any dependency that cannot cross that boundary.
