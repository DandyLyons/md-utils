//
//  Rename.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import PathKit
/// Adds Markdown document behavior to ``CLIEntry.FrontMatterCommands``.
///
/// See <doc:FrontmatterCommands> for workflow details.
extension CLIEntry.FrontMatterCommands {
  /// Rename a frontmatter key
  struct Rename: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "rename",
      abstract: "Rename a key in frontmatter",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Renames an existing frontmatter key to a new name, preserving the value.

        The operation will fail if:
        - The old key doesn't exist
        - The new key already exists (to prevent overwriting)

        Examples:
          # Rename 'date' to 'created' in a single file
          md-utils fm rename --key date --new-key created document.md

          # Rename key across all Markdown files in a directory
          md-utils fm rename --key tags --new-key categories ./docs/
        """),
      aliases: ["rn"]
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var lineCommentOptions: LineCommentFrontMatterOptions

    @Option(name: .shortAndLong, help: "The key to rename")
    var key: String

    @Option(help: "The new key name")
    var newKey: String

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      let files = try options.resolvedFrontMatterPaths(
        includeNonMarkdown: includeNonMD,
        lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
      )

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false

      for file in files {
        do {
          let parsed = try FrontMatterCLIMutator.parsedFile(
            at: file,
            includeNonMarkdown: includeNonMD,
            lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
          )
          var doc = parsed.document

          try doc.renameKey(from: key, to: newKey)

          try FrontMatterCLIMutator.write(doc, parsed: parsed, to: file)
        } catch {
          CLIStyle.writeError("\(CLIStyle.path(file.string)): \(error.localizedDescription)")
          hasErrors = true
          continue
        }
      }

      if hasErrors { throw ExitCode.failure }
    }
  }
}
