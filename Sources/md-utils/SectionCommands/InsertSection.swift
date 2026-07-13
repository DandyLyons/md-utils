//
//  InsertSection.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

/// Adds command implementations to ``CLIEntry``.
///
/// See <doc:ContentSelectionCommands> for workflow details.
extension CLIEntry {
  /// Insert a new section into a Markdown document.
  struct InsertSection: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "insert",
      abstract: "Insert a new contained section into a Markdown document",
      discussion: """
        Inserts a new section before or after an existing section. The inserted
        content may be body-only or may start with a heading that matches --name.
        Heading levels are normalized to keep the inserted content contained in
        one section.

        EXAMPLES:
          md-utils section insert --name "New Section" --into README.md --after "Old Section" --contents "Body text."
          md-utils section insert --name "New Section" --into README.md --after "Old Section" --from-file new-section.txt
          md-utils section insert --name "New Section" --into README.md --before-index 2 < new-section.md
        """
    )

    @Option(name: .long, help: "Name of the new section heading")
    var name: String

    @Option(name: .long, help: "Markdown document to modify", transform: { Path($0) })
    var into: Path

    @Option(name: .long, help: "Insert after the section with this heading text")
    var after: String?

    @Option(
      name: [.customLong("after-index"), .customLong("afterI")],
      help: "Insert after this 1-based heading index"
    )
    var afterIndex: Int?

    @Option(name: .long, help: "Insert before the section with this heading text")
    var before: String?

    @Option(
      name: [.customLong("before-index"), .customLong("beforeI")],
      help: "Insert before this 1-based heading index"
    )
    var beforeIndex: Int?

    @Option(name: .long, help: "Inline body content for the new section")
    var contents: String?

    @Option(
      name: .long,
      help: "Read inserted content from a file",
      transform: { Path($0) }
    )
    var fromFile: Path?

    @Option(name: .long, help: "Explicit heading level for the inserted section (1...6)")
    var level: Int?

    @Flag(name: .long, help: "Use case-sensitive matching for heading names")
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
      let insertedContent = try readInsertedContent()
      let result: MarkdownDocument

      do {
        result = try await doc.insertSection(
          name: name,
          content: insertedContent,
          placement: try placement(),
          level: level,
          caseSensitive: caseSensitive
        )
      } catch let error as SectionExtractorError {
        throw ValidationError(error.description)
      } catch let error as SectionInsertionError {
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
      let placementCount = [after, before].compactMap { $0 }.count
        + [afterIndex, beforeIndex].compactMap { $0 }.count
      guard placementCount == 1 else {
        throw ValidationError("Specify exactly one placement: --after, --after-index, --before, or --before-index.")
      }

      if let afterIndex {
        guard afterIndex >= 1 else {
          throw ValidationError("--after-index must be positive (1-based indexing: 1 = first heading)")
        }
      }
      if let beforeIndex {
        guard beforeIndex >= 1 else {
          throw ValidationError("--before-index must be positive (1-based indexing: 1 = first heading)")
        }
      }
      if let level {
        guard (1...6).contains(level) else {
          throw ValidationError("--level must be between 1 and 6")
        }
      }
      guard !(contents != nil && fromFile != nil) else {
        throw ValidationError("Use only one content source: --contents, --from-file, or stdin.")
      }
    }

    private func placement() throws -> MarkdownDocument.SectionInsertionPlacement {
      if let after {
        return .after(.name(after, caseSensitive: caseSensitive))
      }
      if let afterIndex {
        return .after(.index(afterIndex - 1))
      }
      if let before {
        return .before(.name(before, caseSensitive: caseSensitive))
      }
      if let beforeIndex {
        return .before(.index(beforeIndex - 1))
      }
      throw ValidationError("Specify exactly one placement: --after, --after-index, --before, or --before-index.")
    }

    private func readInsertedContent() throws -> String {
      if let contents {
        return contents
      }

      if let fromFile {
        guard fromFile.exists else {
          throw ValidationError("Content file does not exist: \(fromFile)")
        }
        guard !fromFile.isDirectory else {
          throw ValidationError("--from-file must be a text file, not a directory: \(fromFile)")
        }
        return try fromFile.read()
      }

      var lines: [String] = []
      while let line = readLine(strippingNewline: false) {
        lines.append(line)
      }
      let stdinContent = lines.joined()
      guard !stdinContent.isEmpty else {
        throw ValidationError("No inserted content provided. Use --contents, --from-file, or pipe content via stdin.")
      }
      return stdinContent
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
