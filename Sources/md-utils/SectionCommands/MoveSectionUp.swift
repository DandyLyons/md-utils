//
//  MoveSectionUp.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry {
  /// Move a section up by one position among its siblings.
  struct MoveSectionUp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "move-up",
      abstract: "Move a section up among its siblings",
      discussion: """
        Moves a section (heading + all nested content) up among its sibling headings.
        By default moves one position; use --count to move multiple positions.

        IDENTIFICATION:
          Use --index to specify which heading to move (1-based: 1 = first heading).
          Use --name to move by heading text (case-insensitive by default).
          Use --case-sensitive for case-sensitive name matching.
          Exactly one of --index or --name must be specified.

        EXAMPLES:
          # Move second heading up by one
          md-utils section move-up --index 2 document.md

          # Move by name, up by 2 positions
          md-utils section move-up --name "Contributing" --count 2 document.md

          # Move in place
          md-utils section move-up --name "API" --in-place document.md

        Note: Only single file operations are supported.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Index of the heading to move (1-based: 1 = first heading)"
    )
    var index: Int?

    @Option(
      name: .long,
      help: "Name of the heading to move"
    )
    var name: String?

    @Flag(
      name: .long,
      help: "Use case-sensitive matching for --name (default: case-insensitive)"
    )
    var caseSensitive: Bool = false

    @Option(
      name: [.short, .long],
      help: "Number of positions to move (default: 1)"
    )
    var count: Int = 1

    @Flag(
      name: .long,
      help: "Modify the file in place instead of writing to stdout"
    )
    var inPlace: Bool = false

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
          throw ValidationError("Must specify either --index or --name to identify which section to move.")
        }
      }

      if let idx = index {
        guard idx >= 1 else {
          throw ValidationError("Index must be positive (1-based indexing: 1 = first heading)")
        }
      }

      guard count >= 1 else {
        throw ValidationError("Count must be at least 1")
      }
    }

    private func processFile(_ path: Path) async throws {
      let content: String = try path.read()
      let doc = try MarkdownUtilities.MarkdownDocument(content: content)

      let result: MarkdownDocument
      do {
        if let idx = index {
          result = try await doc.moveSectionUp(at: idx, count: count)
        } else if let headingName = name {
          result = try await doc.moveSectionUp(byName: headingName, caseSensitive: caseSensitive, count: count)
        } else {
          throw ValidationError("Must specify either --index or --name")
        }
      } catch let error as SectionReordererError {
        throw ValidationError(error.description)
      }

      let output = try reconstructDocument(result)

      if inPlace {
        try path.write(output)
      } else {
        print(output)
      }
    }

    private func reconstructDocument(_ doc: MarkdownDocument) throws -> String {
      guard !doc.frontMatter.isEmpty else {
        return doc.body
      }

      let yamlContent = try YAMLConversion.serialize(doc.frontMatter)

      return """
        ---
        \(yamlContent)---
        \(doc.body)
        """
    }
  }
}
