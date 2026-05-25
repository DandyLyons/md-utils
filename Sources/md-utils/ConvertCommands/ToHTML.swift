//
//  ToHTML.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.ConvertCommands {
    /// Convert Markdown to HTML
    struct ToHTML: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-html",
            abstract: "Convert Markdown files to HTML",
            discussion: """
                Converts Markdown files to HTML using the cmark-gfm renderer.
                GFM extensions (tables, autolinks, strikethrough, tag filters, task lists)
                are enabled by default; use --no-X flags to disable individual ones.

                EXAMPLES:
                  # Single file to stdout
                  md-utils convert to-html README.md

                  # Single file to specific file
                  md-utils convert to-html README.md -o output.html

                  # Single file to directory
                  md-utils convert to-html src/README.md -o output/

                  # Batch conversion
                  md-utils convert to-html docs/ -o output/
                  md-utils convert to-html *.md -o output/

                  # In-place conversion (.md → .html)
                  md-utils convert to-html docs/ --in-place
                  md-utils convert to-html file.md --in-place

                  # From stdin
                  cat README.md | md-utils convert to-html
                  echo "# Hello" | md-utils convert to-html

                  # Full HTML document
                  md-utils convert to-html README.md --wrap-document

                  # Disable GFM tables only
                  md-utils convert to-html table.md --no-tables

                  # CommonMark only (no GFM extensions)
                  md-utils convert to-html file.md --no-tables --no-autolinks \\
                    --no-strikethrough --no-tagfilters --no-tasklist

                By default:
                - Single file outputs to stdout
                - Excludes frontmatter from output
                - All GFM extensions enabled
                - Soft breaks preserved (not converted to <br>)
                - Unsafe raw HTML filtered
                """
        )

        @OptionGroup var options: GlobalOptions

        @Option(
            name: [.short, .long],
            help: """
                Output file or directory. For single file: writes to this file or \
                dir/basename.html. For multiple files: must be a directory. \
                If not specified, writes to stdout (single file) or requires \
                --in-place (batch).
                """,
            completion: .file(),
            transform: { Path($0) }
        )
        var output: Path?

        @Flag(
            name: .long,
            help: """
                Convert .md files to .html in their original locations. \
                Cannot be used with --output.
                """
        )
        var inPlace: Bool = false

        @Flag(
            name: .long,
            help: "Wrap output in a minimal HTML document skeleton (<!DOCTYPE html>…)"
        )
        var wrapDocument: Bool = false

        @Flag(
            name: .long,
            help: "Prepend YAML frontmatter as an HTML comment (<!-- … -->)"
        )
        var includeFrontmatter: Bool = false

        @Flag(
            name: .long,
            help: "Render soft line breaks as <br> instead of a space"
        )
        var hardBreaks: Bool = false

        @Flag(
            name: .long,
            help: "Allow raw HTML to pass through unchanged (unsafe)"
        )
        var allowUnsafeHtml: Bool = false

        @Flag(
            name: .long,
            help: "Convert straight quotes to curly, --- to em dashes, -- to en dashes"
        )
        var smartPunctuation: Bool = false

        // MARK: - GFM extension flags (on by default; use --no-X to disable)

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: "Enable GFM pipe tables (use --no-tables to disable)"
        )
        var tables: Bool = true

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: "Enable URL autolinks (use --no-autolinks to disable)"
        )
        var autolinks: Bool = true

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: "Enable ~~strikethrough~~ via double tildes (use --no-strikethrough to disable)"
        )
        var strikethrough: Bool = true

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: "Filter unsafe HTML tags from output (use --no-tagfilters to disable)"
        )
        var tagfilters: Bool = true

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: "Enable - [x] task list checkboxes (use --no-tasklist to disable)"
        )
        var tasklist: Bool = true

        mutating func run() async throws {
            try validateFlags()

            let inputMode = try determineInputMode()

            var extensionOptions: MarkdownExtensionOptions = []
            if tables       { extensionOptions.insert(.tables) }
            if autolinks    { extensionOptions.insert(.autolinks) }
            if strikethrough { extensionOptions.insert(.strikethrough) }
            if tagfilters   { extensionOptions.insert(.tagfilters) }
            if tasklist     { extensionOptions.insert(.tasklist) }

            let conversionOptions = HTMLOptions(
                includeFrontmatter: includeFrontmatter,
                wrapInDocument: wrapDocument,
                hardBreaks: hardBreaks,
                allowUnsafeHTML: allowUnsafeHtml,
                smartPunctuation: smartPunctuation,
                extensions: extensionOptions
            )

            switch inputMode {
            case .stdin:
                try await processStdin(options: conversionOptions)

            case .singleFile(let file):
                try await processSingleFile(file, options: conversionOptions)

            case .multipleFiles(let files):
                try await processMultipleFiles(files, options: conversionOptions)
            }
        }

        // MARK: - Input Mode Detection

        enum InputMode {
            case stdin
            case singleFile(Path)
            case multipleFiles([Path])
        }

        func determineInputMode() throws -> InputMode {
            if options.paths.isEmpty {
                if isatty(STDIN_FILENO) == 0 {
                    return .stdin
                } else {
                    throw ValidationError("No input specified. Provide file paths or pipe input to stdin.")
                }
            }

            let files = try options.resolvedPaths()

            if files.isEmpty {
                throw ValidationError("No Markdown files found to process")
            }

            if files.count == 1 {
                return .singleFile(files[0])
            } else {
                return .multipleFiles(files)
            }
        }

        // MARK: - Validation

        func validateFlags() throws {
            if output != nil && inPlace {
                throw ValidationError("Cannot use both --output and --in-place")
            }
        }

        // MARK: - Processing Methods

        func processStdin(options conversionOptions: HTMLOptions) async throws {
            var stdinContent = ""
            while let line = readLine(strippingNewline: false) {
                stdinContent += line
            }

            guard !stdinContent.isEmpty else {
                throw ValidationError("No input received from stdin")
            }

            let doc = try MarkdownDocument(content: stdinContent)
            let html = try await doc.toHTML(options: conversionOptions)

            if let outputPath = output {
                try outputPath.write(html)
            } else {
                print(html, terminator: "")
            }
        }

        func processSingleFile(_ file: Path, options conversionOptions: HTMLOptions) async throws {
            let content: String = try file.read()
            let doc = try MarkdownDocument(content: content)
            let html = try await doc.toHTML(options: conversionOptions)

            if let outputPath = output {
                let finalPath = resolveOutputPath(outputPath, for: file)
                try finalPath.write(html)
            } else if inPlace {
                let htmlPath = file.parent() + "\(file.lastComponentWithoutExtension).html"
                try htmlPath.write(html)
            } else {
                print(html, terminator: "")
            }
        }

        func processMultipleFiles(_ files: [Path], options conversionOptions: HTMLOptions) async throws {
            if output == nil && !inPlace {
                throw ValidationError(
                    "Multiple input files require --output <directory> or --in-place"
                )
            }

            if let outputPath = output {
                if outputPath.exists && !outputPath.isDirectory {
                    throw ValidationError(
                        "Batch conversion requires output directory, not file: \(outputPath)"
                    )
                }
                if !outputPath.exists {
                    try outputPath.mkpath()
                }
            }

            var successCount = 0
            var errorCount = 0

            for file in files {
                do {
                    let content: String = try file.read()
                    let doc = try MarkdownDocument(content: content)
                    let html = try await doc.toHTML(options: conversionOptions)

                    let finalPath: Path
                    if inPlace {
                        finalPath = file.parent() + "\(file.lastComponentWithoutExtension).html"
                    } else if let outputDir = output {
                        finalPath = outputDir + "\(file.lastComponentWithoutExtension).html"
                    } else {
                        fatalError("Unreachable: validation should have caught this")
                    }

                    if !finalPath.parent().exists {
                        try finalPath.parent().mkpath()
                    }

                    try finalPath.write(html)

                    FileHandle.standardError.write("✓ Converted: \(file) → \(finalPath)\n".data(using: .utf8)!)
                    successCount += 1
                } catch {
                    FileHandle.standardError.write("✗ Error converting \(file): \(error.localizedDescription)\n".data(using: .utf8)!)
                    errorCount += 1
                }
            }

            FileHandle.standardError.write("\nConversion complete:\n".data(using: .utf8)!)
            FileHandle.standardError.write("  Success: \(successCount)\n".data(using: .utf8)!)
            if errorCount > 0 {
                FileHandle.standardError.write("  Errors: \(errorCount)\n".data(using: .utf8)!)
                throw ExitCode.failure
            }
        }

        // MARK: - Helper Methods

        /// Resolves the output path for a single file conversion.
        ///
        /// If `outputPath` is an existing directory (or ends with `/`), returns
        /// `outputPath/basename.html`. Otherwise treats it as the target file.
        func resolveOutputPath(_ outputPath: Path, for inputFile: Path) -> Path {
            if outputPath.isDirectory {
                return outputPath + "\(inputFile.lastComponentWithoutExtension).html"
            }

            if outputPath.string.hasSuffix("/") {
                let dirPath = Path(String(outputPath.string.dropLast()))
                return dirPath + "\(inputFile.lastComponentWithoutExtension).html"
            }

            return outputPath
        }
    }
}
