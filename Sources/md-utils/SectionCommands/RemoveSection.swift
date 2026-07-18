//
//  RemoveSection.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import PathKit
import Yams

/// Adds command implementations to ``CLIEntry``.
///
/// See <doc:ContentSelectionCommands> for workflow details.
extension CLIEntry {
  /// Remove a section from a Markdown document.
  struct RemoveSection: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "remove",
      abstract: "Remove a section and its descendants from a Markdown document",
      discussion: """
        Removes a section (heading + all nested content) from a Markdown file.

        EXAMPLES:
          md-utils section remove --into README.md --name "Deprecated" --in-place
          md-utils section remove --into README.md --index 3
        """
    )

    @Option(name: .long, help: "Markdown document to modify", transform: { Path($0) })
    var into: Path

    @Option(name: .long, help: "Index of the heading to remove (1-based: 1 = first heading)")
    var index: Int?

    @Option(name: .long, help: "Name of the heading to remove")
    var name: String?

    @Flag(name: .long, help: "Use case-sensitive matching for --name")
    var caseSensitive: Bool = false

    @Flag(name: .long, help: "Modify --into in place instead of writing to stdout")
    var inPlace: Bool = false

    @Flag(name: .long, help: "Preview the transformed document without writing files")
    var dryRun: Bool = false

    /// Runs the command using parsed command-line arguments.
    mutating func run() async throws {
      try validateArguments()

      guard into.exists else {
        throw ValidationError("Input document does not exist: \(into)")
      }
      guard !into.isDirectory else {
        throw ValidationError("--into must be a Markdown file, not a directory: \(into)")
      }

      let original: String = try into.read()
      let doc = try MarkdownDocument(content: original)
      let result: MarkdownDocument

      do {
        if let index {
          result = try await doc.removeSection(at: index)
        } else if let name {
          result = try await doc.removeSection(byName: name, caseSensitive: caseSensitive)
        } else {
          throw ValidationError("Must specify either --index or --name to identify which section to remove.")
        }
      } catch let error as SectionExtractorError {
        throw ValidationError(error.description)
      }

      let output = try reconstructDocument(result)
      if inPlace && !dryRun {
        try into.write(output)
      } else {
        print(output)
      }
    }

    private func validateArguments() throws {
      let hasIndex = index != nil
      let hasName = name != nil

      guard hasIndex != hasName else {
        if hasIndex && hasName {
          throw ValidationError("Cannot specify both --index and --name. Use one or the other.")
        }
        throw ValidationError("Must specify either --index or --name to identify which section to remove.")
      }

      if let index {
        guard index >= 1 else {
          throw ValidationError("Index must be positive (1-based indexing: 1 = first heading)")
        }
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
