import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry {
    /// Normalize Markdown formatting conventions.
    struct FormatCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "format",
            abstract: "Normalize Markdown formatting conventions",
            discussion: """
                Apply one or more formatting normalizations to Markdown files.

                BULLET MARKERS:
                  Use --bullets-dashes to convert all unordered list markers to -.
                  Use --bullets-asterisks to convert all unordered list markers to *.
                  These flags are mutually exclusive.

                ITALIC MARKERS:
                  Use --italic-asterisks to convert all italic markers to *...*
                  Use --italic-underscores to convert all italic markers to _..._
                  These flags are mutually exclusive.

                TABLES:
                  Use --normalize-tables to pad table cells so columns align vertically.
                  Use --max-width <n> to cap how far columns are padded (default: 80).
                  Cells whose content already exceeds --max-width are never truncated.

                OUTPUT:
                  By default, formatted content is written to stdout.
                  Use --in-place to modify files in place.

                EXAMPLES:
                  md-utils format --bullets-dashes document.md
                  md-utils format --italic-asterisks document.md
                  md-utils format --normalize-tables document.md
                  md-utils format --bullets-dashes --normalize-tables docs/
                  md-utils format --bullets-dashes --in-place docs/
                """
        )

        @OptionGroup var options: GlobalOptions

        @Flag(name: .customLong("bullets-dashes"),
              help: "Convert unordered list markers to -")
        var bulletsDashes: Bool = false

        @Flag(name: .customLong("bullets-asterisks"),
              help: "Convert unordered list markers to *")
        var bulletsAsterisks: Bool = false

        @Flag(name: .customLong("italic-asterisks"),
              help: "Convert italic/emphasis markers to *...*")
        var italicAsterisks: Bool = false

        @Flag(name: .customLong("italic-underscores"),
              help: "Convert italic/emphasis markers to _..._")
        var italicUnderscores: Bool = false

        @Flag(name: .customLong("normalize-tables"),
              help: "Pad table cells to align columns vertically")
        var normalizeTables: Bool = false

        @Option(name: .customLong("max-width"),
                help: "Cap column padding to this width when normalizing tables (default: 80); content wider than this is never truncated")
        var maxWidth: Int = 80

        @Flag(name: .long,
              help: "Modify files in place instead of writing to stdout")
        var inPlace: Bool = false

        mutating func run() async throws {
            // Validate mutual exclusions
            guard !(bulletsDashes && bulletsAsterisks) else {
                throw ValidationError("--bullets-dashes and --bullets-asterisks are mutually exclusive")
            }
            guard !(italicAsterisks && italicUnderscores) else {
                throw ValidationError("--italic-asterisks and --italic-underscores are mutually exclusive")
            }

            // Require at least one formatting option
            guard bulletsDashes || bulletsAsterisks || italicAsterisks
                    || italicUnderscores || normalizeTables else {
                throw ValidationError(
                    "Specify at least one formatting option (e.g. --bullets-dashes)"
                )
            }

            // Build FormattingOptions
            let bulletMarker: BulletNormalizer.Marker? =
                bulletsDashes ? .dash : bulletsAsterisks ? .asterisk : nil
            let italicMarker: ItalicNormalizer.Marker? =
                italicAsterisks ? .asterisk : italicUnderscores ? .underscore : nil
            let formatOptions = FormattingOptions(
                bulletMarker: bulletMarker,
                italicMarker: italicMarker,
                normalizeTables: normalizeTables,
                tableMaxWidth: maxWidth
            )

            // Resolve files
            let files = try options.resolvedPaths()
            guard !files.isEmpty else {
                throw ValidationError("No Markdown files found to process")
            }

            // Process each file
            for file in files {
                let content: String = try file.read()
                let doc = try MarkdownDocument(content: content)
                let formatted = try await doc.format(options: formatOptions)
                let output = try reconstructOutput(formatted)

                if inPlace {
                    try file.write(output)
                    if files.count > 1 {
                        FileHandle.standardError.write(
                            "Formatted: \(file)\n".data(using: .utf8) ?? Data()
                        )
                    }
                } else {
                    if files.count > 1 { print("--- \(file) ---") }
                    print(output)
                }
            }
        }

        private func reconstructOutput(_ doc: MarkdownDocument) throws -> String {
            guard !doc.frontMatter.isEmpty else { return doc.body }
            let yaml = try YAMLConversion.serialize(doc.frontMatter)
            return "---\n\(yaml)---\n\(doc.body)"
        }
    }
}
