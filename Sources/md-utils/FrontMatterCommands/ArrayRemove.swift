//
//  ArrayRemove.swift
//  md-utils
//
//  Remove values from arrays in frontmatter
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry.FrontMatterCommands.ArrayCommands {
  struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "remove",
      abstract: "Remove first occurrence of a value from an array in frontmatter",
      discussion: """
        Remove the first occurrence of a value from an array. If the value appears
        multiple times, only the first occurrence is removed.

        Files where the value is not found are skipped.

        EXAMPLES:
          # Remove "draft" tag from posts
          md-utils fm array remove --key tags --value draft posts/*.md

          # Remove specific alias
          md-utils fm array remove --key aliases --value "Old Name" post.md

        CASE SENSITIVITY:
          Use --case-insensitive for case-insensitive matching:
          md-utils fm array remove --key tags --value SWIFT --case-insensitive posts/*.md
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .shortAndLong, help: "The frontmatter key (must be an array)")
    var key: String

    @Option(name: .shortAndLong, help: "The value to remove from the array")
    var value: String

    @Flag(name: .long, help: "Case-insensitive comparison")
    var caseInsensitive: Bool = false

    mutating func run() async throws {
      var processedCount = 0
      var skippedCount = 0
      let paths = try options.resolvedPaths()

      guard !paths.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      for path in paths {
        // Parse file
        let content: String = try path.read()
        var doc = try MarkdownDocument(content: content)

        // Validate array exists
        let sequence = try ArrayHelpers.validateArrayKey(key, in: doc, path: path)

        // Attempt to remove value
        guard let updatedSequence = ArrayHelpers.removeFirst(
          value: value,
          from: sequence,
          caseInsensitive: caseInsensitive
        ) else {
          skippedCount += 1
          continue
        }

        doc.frontMatter[key] = .sequence(updatedSequence)

        // Write back
        let updatedContent = try doc.render()
        try updatedContent.write(toFile: path.string, atomically: true, encoding: .utf8)
        processedCount += 1
      }

      // Summary output (to stderr, doesn't interfere with piping)
      if processedCount == 0 {
        fputs("No files were modified (value '\(value)' not found in any arrays)\n", stderr)
      } else {
        fputs("Updated \(processedCount) file(s)\n", stderr)
        if skippedCount > 0 {
          fputs("Skipped \(skippedCount) file(s) where value was not found\n", stderr)
        }
      }
    }
  }
}
