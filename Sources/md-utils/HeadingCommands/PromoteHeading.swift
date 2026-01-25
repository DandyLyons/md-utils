//
//  PromoteHeading.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry {
  /// Promote headings (decrease level) in Markdown files.
  struct PromoteHeading: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "promote",
      abstract: "Promote headings (decrease level) in Markdown files",
      discussion: """
        Promotes (decreases level) a heading and optionally its children.
        For example, H2 → H1, H3 → H2.

        Headings at H1 cannot be promoted further and will remain at H1.

        Use --index to specify which heading to promote (1-based: 1 = first heading).
        Use --target-only to promote only the specified heading without children.
        Use --in-place to modify files directly instead of outputting to stdout.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Index of the heading to promote (1-based: 1 = first heading)"
    )
    var index: Int

    @Flag(
      name: .long,
      help: "Promote only the target heading, not its children"
    )
    var targetOnly: Bool = false

    @Flag(
      name: .long,
      help: "Modify the file in place instead of writing to stdout"
    )
    var inPlace: Bool = false

    mutating func run() async throws {
      // Validate index
      guard index >= 1 else {
        throw ValidationError("Index must be positive (1-based indexing: 1 = first heading)")
      }

      // Resolve paths
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      // Process each file
      for file in files {
        try await processFile(file, totalFiles: files.count)
      }
    }

    private func processFile(_ path: Path, totalFiles: Int) async throws {
      // Read file content
      let content: String = try path.read()

      // Parse document
      let doc = try MarkdownUtilities.MarkdownDocument(content: content)

      // Promote heading
      let result: MarkdownDocument
      do {
        result = try await doc.promoteHeading(at: index, includeChildren: !targetOnly)
      } catch let error as HeadingAdjusterError {
        // Provide helpful error messages
        throw ValidationError(error.description)
      }

      // Reconstruct full document (frontmatter + body)
      let output = try reconstructDocument(result)

      if inPlace {
        // Write back to file
        try path.write(output)

        // Print status to stderr if processing multiple files
        if totalFiles > 1 {
          FileHandle.standardError.write("Promoted heading in: \(path)\n".data(using: .utf8)!)
        }
      } else {
        // Output to stdout
        if totalFiles > 1 {
          // Print file header if processing multiple files
          print("--- \(path) ---")
        }
        print(output)
      }
    }

    /// Reconstructs the full document including frontmatter if present.
    private func reconstructDocument(_ doc: MarkdownDocument) throws -> String {
      // If frontmatter is empty, return just the body
      guard !doc.frontMatter.isEmpty else {
        return doc.body
      }

      // Serialize frontmatter
      let yamlContent = try YAMLConversion.serialize(doc.frontMatter)

      // Reconstruct with frontmatter delimiters
      return """
        ---
        \(yamlContent)---
        \(doc.body)
        """
    }
  }
}
