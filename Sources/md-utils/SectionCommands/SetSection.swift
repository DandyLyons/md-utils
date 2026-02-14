//
//  SetSection.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry {
  /// Replace a section's content in a Markdown document.
  struct SetSection: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "set",
      abstract: "Replace a section's body content in a Markdown document",
      discussion: """
        Replaces the body of a section (all content below the heading, up to the next
        same-level or higher heading). The heading itself is preserved — only the body
        content beneath it is replaced. This is analogous to `fm set` for front matter.

        Reads the replacement content from stdin or from a file specified with --input.

        IDENTIFICATION:
          Use --index to specify which heading (1-based: 1 = first heading).
          Use --name to identify by heading text (case-insensitive by default).
          Use --case-sensitive for case-sensitive name matching.
          Exactly one of --index or --name must be specified.

        EXAMPLES:
          # Replace body of a section by name from stdin
          echo "new body content" | md-utils section set --name "Introduction" document.md

          # Replace by index from a file
          md-utils section set --index 2 --input new-body.md document.md

          # Replace in place
          echo "updated content" | md-utils section set --name "Notes" --in-place document.md

        Note: Only single file operations are supported.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Index of the heading to replace (1-based: 1 = first heading)"
    )
    var index: Int?

    @Option(
      name: .long,
      help: "Name of the heading to replace"
    )
    var name: String?

    @Flag(
      name: .long,
      help: "Use case-sensitive matching for --name (default: case-insensitive)"
    )
    var caseSensitive: Bool = false

    @Option(
      name: .long,
      help: "Read replacement content from a file instead of stdin",
      transform: { Path($0) }
    )
    var input: Path?

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
          throw ValidationError("Must specify either --index or --name to identify which section to replace.")
        }
      }

      if let idx = index {
        guard idx >= 1 else {
          throw ValidationError("Index must be positive (1-based indexing: 1 = first heading)")
        }
      }
    }

    private func readReplacementContent() throws -> String {
      if let inputPath = input {
        guard inputPath.exists else {
          throw ValidationError("Input file does not exist: \(inputPath)")
        }
        return try inputPath.read()
      }

      // Read from stdin
      var lines: [String] = []
      while let line = readLine(strippingNewline: false) {
        lines.append(line)
      }
      let content = lines.joined()

      guard !content.isEmpty else {
        throw ValidationError("No replacement content provided. Pipe content via stdin or use --input <file>.")
      }

      // Trim a single trailing newline if present (stdin typically adds one)
      if content.hasSuffix("\n") {
        return String(content.dropLast())
      }
      return content
    }

    private func processFile(_ path: Path) async throws {
      let content: String = try path.read()
      let doc = try MarkdownDocument(content: content)

      let replacementContent = try readReplacementContent()

      let result: MarkdownDocument
      do {
        if let idx = index {
          result = try await doc.replaceSection(at: idx, with: replacementContent)
        } else if let headingName = name {
          result = try await doc.replaceSection(
            byName: headingName,
            caseSensitive: caseSensitive,
            with: replacementContent
          )
        } else {
          throw ValidationError("Must specify either --index or --name")
        }
      } catch let error as SectionExtractorError {
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
