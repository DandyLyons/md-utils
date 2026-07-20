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
| Portable Core | Every Swift file under `Types/` and `Rules/` | Operates on canonical record strings, explicit logical context, supplied definitions, and host-provided schema resources. It does not discover or mutate host state. |
| Native integration | Every Swift file under `Types/` | Loads definitions and schema resources from native paths, adapts files to records, and performs atomic filesystem writes. |
| Native integration | Every Swift file under `FileMetadata/` | Reads filesystem attributes and, on Darwin, extended attributes. |
| Native integration | `FormatConversion/CSV/CSVConverter.swift` and `CSVOptions.swift` | Absolute and relative metadata columns currently use PathKit and implicit current-working-directory context. |
| Native integration | `Wikilink/WikilinkResolver.swift` and `ResolvedWikilink.swift` | Scans directories and exposes PathKit paths in the public API. |
| CLI only | Every Swift file under `Sources/md-utils/` | Owns ArgumentParser commands, terminal formatting, file orchestration, and process exit behavior. |

Directory paths in the table are relative to `Sources/MarkdownUtilitiesCore/`, `Sources/MarkdownUtilities/`, or the explicitly named `Sources/md-utils/` directory.

## Dependency Assessment

| Dependency | Layer | Linux status | WebAssembly status |
|---|---|---|---|
| Swift standard library and Foundation | Core | Verified by the Linux container build and Core tests. | Verified with the official Swift 6.3.1 WASI SDK. CoreFoundation requires the WASI signal and memory-mapping emulation definitions and libraries. |
| MarkdownSyntax and swift-cmark | Core | Verified by the Linux container build and Core tests. | MarkdownSyntax 1.3.0 and swift-cmark 0.7.1 compile and run under WASI, including GFM task lists and tables. |
| swift-parsing | Core | Verified by the Linux container build and parser tests. | Verified while building and running the Core WASI smoke target. |
| Yams and libYAML | Core | Verified by the Linux container build and frontmatter tests. | libYAML and Yams compile and run under WASI. Yams 6.2.0 requires the version-checked `DBL_DECIMAL_DIG` compatibility patch described in [WebAssembly Support](webassembly.md). |
| JSONSchema | Core | Draft 2020-12 validation, external graph compilation, and the Linux Core build are verified. | Draft 2020-12 assessment runs under WASI. JSONSchema.swift 0.6.0 requires the version-checked WASI `NSNumber` compatibility patch described in [WebAssembly Support](webassembly.md). |
| PathKit | Native only | Supported by the native package; excluded from Core. | Out of scope because it is not a Core dependency. |
| ArgumentParser, JMESPath, Rainbow | CLI only | Outside the Core boundary. | Out of scope because the CLI is not a WebAssembly target. |

Linux verification uses Swift 6.2 in `Dockerfile.core-linux`. A successful image build runs `swift build --target MarkdownUtilitiesCore`, then runs the isolated `IntegrationTests/LinuxCoreSmoke/` executable against Core. The full focused `MarkdownUtilitiesCoreTests` target remains part of `swift test`; SwiftPM test filtering cannot avoid compiling unrelated package test targets.

The Core schema adapter performs no implicit retrieval. A caller supplies `MarkdownSchemaResourceProvider`; registry construction resolves and caches the immutable graph, rewrites external references to canonical resource identifiers, and rejects missing resources, cycles, and conflicting `$id` values before assessment. The current JSONSchema dependency passes the package's draft 2020-12 `const`, `contains`, `allOf`, required-property, and nested-reference coverage on macOS, compiles in the Linux Core container, and performs representative draft 2020-12 assessment in the WASI smoke target.

## Placement Rules

- Put APIs in Core when all inputs are supplied explicitly and behavior depends only on those inputs.
- Put directory scanning, path discovery, file metadata, extended attributes, environment access, and host configuration in `MarkdownUtilities`.
- Put argument parsing, terminal styling, printing, and exit codes in `md-utils`.
- Do not use conditional compilation to hide an integration inside Core; introduce a native adapter instead.
- Re-run the Linux container whenever Core sources or direct dependencies change.

## Import Migration

Portable types formerly declared by `MarkdownUtilities`, including `MarkdownDocument`, now belong to the `MarkdownUtilitiesCore` module. Source files using those APIs must import Core explicitly. Files that combine portable document operations with native resolvers, CSV path metadata, or file metadata import both modules.

## WebAssembly Verification

Run `scripts/build-wasm.sh` to compile Core and execute the WASI smoke target with the official Swift 6.3.1 WebAssembly SDK. Detailed installation, dependency patching, smoke coverage, artifact location, and remaining host-interface work are documented in [WebAssembly Support](webassembly.md).
