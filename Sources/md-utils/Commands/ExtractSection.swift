//
//  ExtractSection.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry {
  /// Extract a section from Markdown files.
  struct ExtractSection: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "extract",
      abstract: "Extract a section from Markdown files",
      discussion: """
        Extracts a section (heading + all nested content) from a Markdown file.

        A section consists of a heading and all content under it until the next
        same-level or higher heading.

        Use --index to specify which heading to extract (1-based: 1 = first heading).
        Use --output to save extracted section to a file (default: stdout).
        Use --remove to remove the section from the source.
        Use --in-place to save changes to the source file (requires --remove).

        Note: Only single file operations are supported. Batch operations are not yet implemented.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Index of the heading to extract (1-based: 1 = first heading)"
    )
    var index: Int

    @Option(
      name: [.short, .long],
      help: "Output file path for the extracted section"
    )
    var output: String?

    @Flag(
      name: .long,
      help: "Remove the section from the source document"
    )
    var remove: Bool = false

    @Flag(
      name: .long,
      help: "Modify the source file in place (requires --remove)"
    )
    var inPlace: Bool = false

    mutating func run() async throws {
      // Validate index
      guard index >= 1 else {
        throw ValidationError("Index must be positive (1-based indexing: 1 = first heading)")
      }

      // Validate --in-place requires --remove
      guard !inPlace || remove else {
        throw ValidationError("--in-place requires --remove flag")
      }

      // Resolve paths
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      // Only support single file operations
      guard files.count == 1 else {
        throw ValidationError("Batch operations not supported. Please specify a single file.")
      }

      let file = files[0]
      try await processFile(file)
    }

    private func processFile(_ path: Path) async throws {
      // Read file content
      let content: String = try path.read()

      // Parse document
      let doc = try MarkdownUtilities.MarkdownDocument(content: content)

      // Extract section
      let (extracted, updated): (MarkdownDocument, MarkdownDocument?)
      do {
        (extracted, updated) = try await doc.extractSection(at: index, removeFromOriginal: remove)
      } catch let error as SectionExtractorError {
        throw ValidationError(error.description)
      }

      // Reconstruct extracted section content
      let extractedOutput = try reconstructDocument(extracted)

      // Handle extracted section output
      if let outputPath = output {
        // Write extracted section to output file
        let outputPathKit = Path(outputPath)
        try outputPathKit.write(extractedOutput)
        FileHandle.standardError.write("Extracted section written to: \(outputPath)\n".data(using: .utf8)!)
      } else {
        // Output extracted section to stdout
        print(extractedOutput)
      }

      // Handle source file modification
      if remove {
        if inPlace {
          // Write updated content back to source
          if let updatedDoc = updated {
            let updatedOutput = try reconstructDocument(updatedDoc)
            try path.write(updatedOutput)
            FileHandle.standardError.write("Source file updated: \(path)\n".data(using: .utf8)!)
          }
        } else {
          // Warn user that changes were not saved
          FileHandle.standardError.write("Warning: Section removed but not saved. Use --in-place to modify the file.\n".data(using: .utf8)!)
        }
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
