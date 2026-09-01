//
//  SortKeys.swift
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
  /// Sort keys in frontmatter
  struct SortKeys: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "sort-keys",
      abstract: "Sort keys in frontmatter",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Sorts the frontmatter keys alphabetically or by key length.

        The sorting can be reversed using the --reverse flag.

        Examples:
          # Sort keys alphabetically in a single file
          md-utils fm sort-keys document.md

          # Sort keys in reverse alphabetical order
          md-utils fm sort-keys --reverse document.md

          # Sort keys by length across all Markdown files in a directory
          md-utils fm sort-keys --method length ./docs/
        """),
      aliases: ["sk"]
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var lineCommentOptions: LineCommentFrontMatterOptions

    @Option(name: [.customShort("m"), .customLong("method")], help: "The sorting method to use (alphabetical, length)")
    var method: MarkdownDocument.SortMethod = .alphabetical

    @Flag(name: .long, help: "Reverse the sorting order")
    var reverse: Bool = false

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
          if case .wrapped = parsed.syntax, parsed.wrappedBlock == nil {
            continue
          }
          var doc = parsed.document

          doc.sortKeys(by: method, reverse: reverse)

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
/// Adds command-line argument parsing to `MarkdownDocument.SortMethod`.
///
/// See <doc:FrontmatterCommands> for workflow details.
extension MarkdownDocument.SortMethod: ExpressibleByArgument {}
