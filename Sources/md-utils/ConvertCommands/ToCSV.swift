//
//  ToCSV.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.ConvertCommands {
    /// Convert Markdown files with frontmatter to CSV
    struct ToCSV: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-csv",
            abstract: "Convert Markdown files with frontmatter to CSV format",
            discussion: """
                Converts a directory of Markdown files with YAML frontmatter into a single CSV file.
                Each YAML key becomes a column, and each file becomes a row.

                EXAMPLES:
                  # Convert directory to CSV
                  md-utils convert to-csv blog/

                  # With custom output
                  md-utils convert to-csv blog/ -o posts.csv

                  # Include metadata columns
                  md-utils convert to-csv blog/ --include-meta fileName,relPath

                  # Exclude body column
                  md-utils convert to-csv blog/ --no-body

                COLUMN ORDERING:
                  1. Metadata columns (if specified): $fileName, $relPath, $absPath
                  2. Body column (if enabled): $body
                  3. Frontmatter columns (alphabetically sorted)

                FILES WITHOUT FRONTMATTER:
                  Files without frontmatter are included with empty frontmatter columns.
                  The $body column (if enabled) will still contain their content.

                NESTED YAML:
                  Nested YAML structures (arrays, objects) are serialized as JSON strings.

                By default:
                - Includes body content in $body column
                - No metadata columns
                - Outputs to {inputFolder}.csv
                """
        )

        @OptionGroup var options: GlobalOptions

        @Option(
            name: [.short, .long],
            help: """
                Output CSV file path. If not specified, uses {inputFolder}.csv \
                or output.csv if input is not a single directory.
                """,
            completion: .file(),
            transform: { Path($0) }
        )
        var output: Path?

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: "Include $body column with document body content (use --no-body to exclude)"
        )
        var body: Bool = true

        @Option(
            name: .long,
            help: """
                Comma-separated list of metadata columns to include. \
                Available: fileName, relPath, absPath
                """,
            transform: parseMetadataColumns
        )
        var includeMeta: Set<CSVOptions.MetadataColumn>?

        mutating func run() async throws {
            // Resolve input files
            let files = try options.resolvedPaths()

            // Validate: must have at least one file
            guard !files.isEmpty else {
                throw ValidationError("No Markdown files found to process")
            }

            // Load all documents with error handling
            var documents: [(path: String, document: MarkdownDocument)] = []
            var errorCount = 0

            for file in files {
                do {
                    let content: String = try file.read()
                    let doc = try MarkdownDocument(content: content)
                    documents.append((file.string, doc))
                } catch {
                    FileHandle.standardError.write("Error loading \(file): \(error.localizedDescription)\n")
                    errorCount += 1
                }
            }

            // Check if we have any valid documents
            guard !documents.isEmpty else {
                FileHandle.standardError.write("No valid Markdown files could be loaded\n")
                throw ExitCode.failure
            }

            // Create CSV options
            let csvOptions = CSVOptions(
                includeBody: body,
                metadataColumns: includeMeta ?? [],
                baseDirectory: options.paths.first?.isDirectory == true ? options.paths.first?.string : nil
            )

            // Convert to CSV
            let converter = CSVConverter()
            let csv: String
            do {
                csv = try converter.convert(documents: documents, options: csvOptions)
            } catch {
                FileHandle.standardError.write("Error converting to CSV: \(error.localizedDescription)\n")
                throw ExitCode.failure
            }

            // Determine output path
            let outputPath = try determineOutputPath(inputFiles: files)

            // Write CSV file
            do {
                try outputPath.write(csv)
                FileHandle.standardError.write("CSV written to: \(outputPath)\n")
            } catch {
                FileHandle.standardError.write("Error writing CSV to \(outputPath): \(error.localizedDescription)\n")
                throw ExitCode.failure
            }

            // Print summary
            FileHandle.standardError.write("\nConversion complete:\n")
            FileHandle.standardError.write("  Files processed: \(documents.count)\n")
            if errorCount > 0 {
                FileHandle.standardError.write("  Errors: \(errorCount)\n")
                throw ExitCode.failure
            }
        }

        // MARK: - Helper Methods

        /// Determine the output path for the CSV file
        func determineOutputPath(inputFiles: [Path]) throws -> Path {
            if let userOutput = output {
                return userOutput
            }

            // Determine default output path
            // If input is a single directory, use {directoryName}.csv
            if options.paths.count == 1, let firstPath = options.paths.first, firstPath.isDirectory {
                let dirName = firstPath.lastComponent
                let outputName = "\(dirName).csv"
                return Path.current + outputName
            }

            // Otherwise, use "output.csv"
            return Path.current + "output.csv"
        }

        /// Parse comma-separated metadata columns
        static func parseMetadataColumns(_ value: String) throws -> Set<CSVOptions.MetadataColumn> {
            let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var columns = Set<CSVOptions.MetadataColumn>()

            for part in parts {
                switch part.lowercased() {
                case "filename":
                    columns.insert(.fileName)
                case "relpath":
                    columns.insert(.relPath)
                case "abspath":
                    columns.insert(.absPath)
                default:
                    throw ValidationError("Unknown metadata column: \(part). Valid options: fileName, relPath, absPath")
                }
            }

            return columns
        }
    }
}
