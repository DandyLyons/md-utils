//
//  Has.swift
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
  /// Check if a frontmatter key exists
  struct Has: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "has",
      abstract: "Check if a frontmatter key exists",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Checks whether a specified key exists in the frontmatter.

        Prints 'true' if the key exists, 'false' otherwise.
        Always exits with success code (0), even when the key doesn't exist.
        When processing multiple files, the filename is included in the output.
        """)
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var lineCommentOptions: LineCommentFrontMatterOptions

    @Option(name: .long, help: "The frontmatter key to check")
    var key: String

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      let timer = CommandTimer()
      let files = try options.resolvedFrontMatterPaths(
        includeNonMarkdown: includeNonMD,
        lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
      )

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false
      var checkedCount = 0

      for file in files {
        do {
          let doc = try FrontMatterCLIReader.document(
            at: file,
            includeNonMarkdown: includeNonMD,
            lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
          )
          let exists = doc.hasKey(key)

          if files.count > 1 {
            print("\(file): \(exists)")
          } else {
            print(exists)
          }
          checkedCount += 1
        } catch {
          CLIStyle.writeError("\(CLIStyle.path(file.string)): \(error.localizedDescription)")
          hasErrors = true
          continue
        }
      }

      timer.writeStatus("Checked frontmatter key \"\(key)\" in \(checkedCount) file(s)")
      if hasErrors { throw ExitCode.failure }
    }
  }
}
