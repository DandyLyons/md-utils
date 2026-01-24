//
//  ArrayAppend.swift
//  md-utils
//
//  Append values to end of arrays in frontmatter
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry.FrontMatterCommands.ArrayCommands {
  struct Append: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "append",
      abstract: "Append a value to the end of an array in frontmatter",
      discussion: """
        Add a value to the end of an array in frontmatter. If the key doesn't
        exist, it will be created as a new array with the value. If the key exists
        but is not an array, an error will be thrown.

        EXAMPLES:
          # Add "tutorial" tag to all posts
          md-utils fm array append --key tags --value tutorial posts/*.md

          # Add alias to specific file (creates 'aliases' key if it doesn't exist)
          md-utils fm array append --key aliases --value "New Alias" post.md

        SKIP DUPLICATES:
          Use --skip-duplicates to only add if value doesn't already exist:
          md-utils fm array append --key tags --value swift --skip-duplicates posts/*.md

        CASE INSENSITIVE:
          Use --case-insensitive for case-insensitive duplicate checking:
          md-utils fm array append --key tags --value SWIFT --case-insensitive --skip-duplicates posts/*.md
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .shortAndLong, help: "The frontmatter key (must be an array)")
    var key: String

    @Option(name: .shortAndLong, help: "The value to append to the array")
    var value: String

    @Flag(name: .long, help: "Skip if value already exists in array")
    var skipDuplicates: Bool = false

    @Flag(name: .long, help: "Case-insensitive duplicate check")
    var caseInsensitive: Bool = false

    mutating func run() async throws {
      let paths = try options.resolvedPaths()

      guard !paths.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      for path in paths {
        // Parse file
        let content: String = try path.read()
        var doc = try MarkdownDocument(content: content)

        // Get array (creates empty if doesn't exist, errors if not an array)
        let sequence = try ArrayHelpers.getOrCreateArrayKey(key, in: doc, path: path)

        // Check for duplicates if requested
        if skipDuplicates {
          if ArrayHelpers.containsValue(value, in: sequence, caseInsensitive: caseInsensitive) {
            continue
          }
        }

        // Append value
        let updatedSequence = ArrayHelpers.append(value: value, to: sequence)
        doc.frontMatter[key] = .sequence(updatedSequence)

        // Write back
        let updatedContent = try doc.render()
        try updatedContent.write(toFile: path.string, atomically: true, encoding: .utf8)
      }
    }
  }
}
