//
//  MoveSectionTo.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry {
  /// Move a section to a specific position among its siblings.
  struct MoveSectionTo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "move-to",
      abstract: "Move a section to a specific position among its siblings",
      discussion: """
        Moves a section (heading + all nested content) to a specific position
        among its sibling headings.

        IDENTIFICATION:
          Use --index to specify which heading to move (1-based: 1 = first heading).
          Use --name to move by heading text (case-insensitive by default).
          Use --case-sensitive for case-sensitive name matching.
          Exactly one of --index or --name must be specified.

        POSITION:
          Use --position to specify the target position among siblings (1-based).
          For example, --position 1 moves the section to be the first sibling.

        EXAMPLES:
          # Move third heading to first position
          md-utils section move-to --index 3 --position 1 document.md

          # Move by name to last position
          md-utils section move-to --name "Appendix" --position 3 document.md

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
      name: .long,
      help: "Target position among siblings (1-based: 1 = first sibling)"
    )
    var position: Int

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

      guard position >= 1 else {
        throw ValidationError("Position must be positive (1-based: 1 = first sibling)")
      }
    }

    private func processFile(_ path: Path) async throws {
      let content: String = try path.read()
      let doc = try MarkdownUtilities.MarkdownDocument(content: content)

      let result: MarkdownDocument
      do {
        if let idx = index {
          result = try await doc.moveSection(at: idx, toPosition: position)
        } else if let headingName = name {
          result = try await doc.moveSection(
            byName: headingName,
            caseSensitive: caseSensitive,
            toPosition: position
          )
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
