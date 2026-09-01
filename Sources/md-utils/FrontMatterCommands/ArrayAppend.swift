//
//  ArrayAppend.swift
//  md-utils
//
//  Append values to end of arrays in frontmatter
//

import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import PathKit
import Yams
/// Adds Markdown document behavior to ``CLIEntry.FrontMatterCommands``.
///
/// See <doc:FrontmatterCommands> for workflow details.
extension CLIEntry.FrontMatterCommands.ArrayCommands {
  /// Defines the `ArrayAppend` command behavior.
  ///
  /// See <doc:FrontmatterCommands> for workflow details.
  struct Append: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "append",
      abstract: "Append a value to the end of an array in frontmatter",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
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
        """)
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var lineCommentOptions: LineCommentFrontMatterOptions

    @Option(name: .shortAndLong, help: "The frontmatter key (must be an array)")
    var key: String

    @Option(name: .shortAndLong, help: "The value to append to the array")
    var value: String

    @Option(name: .long, help: "Frontmatter format to create or convert to (yaml, toml)")
    var frontmatterFormat: FrontMatterFormat?

    @Flag(name: .long, help: "Skip if value already exists in array")
    var skipDuplicates: Bool = false

    @Flag(name: .long, help: "Case-insensitive duplicate check")
    var caseInsensitive: Bool = false

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false

    @Flag(name: .long, help: "Authorize frontmatter creation in non-Markdown files")
    var createFrontmatter = false
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      let timer = CommandTimer()
      let paths = try options.resolvedFrontMatterPaths(
        includeNonMarkdown: includeNonMD,
        lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
      )

      guard !paths.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false
      var updatedCount = 0

      for path in paths {
        do {
          let parsed = try FrontMatterCLIMutator.parsedFile(
            at: path,
            includeNonMarkdown: includeNonMD,
            lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
          )
          var doc = parsed.document
          if let frontmatterFormat { doc.frontMatterFormat = frontmatterFormat }

          // Get array (creates empty if doesn't exist, errors if not an array)
          let sequence = try ArrayHelpers.getOrCreateArrayKey(key, in: doc, path: path)

          // Check for duplicates if requested
          if skipDuplicates {
            if ArrayHelpers.containsValue(value, in: sequence, caseInsensitive: caseInsensitive) {
              continue
            }
          }

          try FrontMatterCLIMutator.authorizeCreationIfNeeded(
            for: parsed,
            options: options,
            createFrontmatter: createFrontmatter
          )

          // Append value
          let updatedSequence = ArrayHelpers.append(value: value, to: sequence)
          doc.frontMatter[key] = .array(updatedSequence)

          // Write back
          try FrontMatterCLIMutator.write(doc, parsed: parsed, to: path)
          updatedCount += 1
        } catch {
          CLIStyle.writeError("\(CLIStyle.path(path.string)): \(error.localizedDescription)")
          hasErrors = true
          continue
        }
      }

      timer.writeStatus("Appended value to frontmatter array \"\(key)\" in \(updatedCount) file(s)")
      if hasErrors { throw ExitCode.failure }
    }
  }
}
