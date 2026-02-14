//
//  GetSection.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry {
  /// Get a section's content from a Markdown document.
  struct GetSection: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "get",
      abstract: "Get a section from a Markdown document",
      discussion: """
        Extracts a section (heading + all nested content) and outputs it.

        IDENTIFICATION:
          Use --index to specify which heading to get (1-based: 1 = first heading).
          Use --name to get by heading text (case-insensitive by default).
          Use --case-sensitive for case-sensitive name matching.
          Exactly one of --index or --name must be specified.

        EXAMPLES:
          # Get the first section
          md-utils section get --index 1 document.md

          # Get by name
          md-utils section get --name "Contributing" document.md

          # Get by name (case-sensitive) and write to file
          md-utils section get --name "API" --case-sensitive --output api.md document.md

        Note: Only single file operations are supported.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Index of the heading to get (1-based: 1 = first heading)"
    )
    var index: Int?

    @Option(
      name: .long,
      help: "Name of the heading to get"
    )
    var name: String?

    @Flag(
      name: .long,
      help: "Use case-sensitive matching for --name (default: case-insensitive)"
    )
    var caseSensitive: Bool = false

    @Option(
      name: [.short, .long],
      help: "Write output to a file instead of stdout",
      transform: { Path($0) }
    )
    var output: Path?

    mutating func run() async throws {
      try validateArguments()

      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      guard files.count == 1 else {
        throw ValidationError("Batch operations not supported. Please specify a single file.")
      }

      try await processFile(files[0])
    }

    private func validateArguments() throws {
      let hasIndex = index != nil
      let hasName = name != nil

      guard hasIndex != hasName else {
        if hasIndex && hasName {
          throw ValidationError("Cannot specify both --index and --name. Use one or the other.")
        } else {
          throw ValidationError("Must specify either --index or --name to identify which section to get.")
        }
      }

      if let idx = index {
        guard idx >= 1 else {
          throw ValidationError("Index must be positive (1-based indexing: 1 = first heading)")
        }
      }
    }

    private func processFile(_ path: Path) async throws {
      let content: String = try path.read()
      let doc = try MarkdownDocument(content: content)

      let extracted: MarkdownDocument
      do {
        if let idx = index {
          let (result, _) = try await doc.extractSection(at: idx)
          extracted = result
        } else if let headingName = name {
          let (result, _) = try await doc.extractSection(
            byName: headingName,
            caseSensitive: caseSensitive
          )
          extracted = result
        } else {
          throw ValidationError("Must specify either --index or --name")
        }
      } catch let error as SectionExtractorError {
        throw ValidationError(error.description)
      }

      let sectionContent = extracted.body

      if let outputPath = output {
        try outputPath.write(sectionContent)
      } else {
        print(sectionContent)
      }
    }
  }
}
