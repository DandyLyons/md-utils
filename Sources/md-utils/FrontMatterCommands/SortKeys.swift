//
//  SortKeys.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.FrontMatterCommands {
  /// Sort keys in frontmatter
  struct SortKeys: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "sort-keys",
      abstract: "Sort keys in frontmatter",
      discussion: """
        Sorts the frontmatter keys alphabetically or by key length.

        The sorting can be reversed using the --reverse flag.

        Examples:
          # Sort keys alphabetically in a single file
          md-utils fm sort-keys document.md

          # Sort keys in reverse alphabetical order
          md-utils fm sort-keys --reverse document.md

          # Sort keys by length across all Markdown files in a directory
          md-utils fm sort-keys --method length ./docs/
        """,
      aliases: ["sk"]
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: [.customShort("m"), .customLong("method")], help: "The sorting method to use (alphabetical, length)")
    var method: MarkdownDocument.SortMethod = .alphabetical

    @Flag(name: .long, help: "Reverse the sorting order")
    var reverse: Bool = false

    mutating func run() async throws {
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false

      for file in files {
        do {
          let content: String = try file.read()
          var doc = try MarkdownDocument(content: content)

          doc.sortKeys(by: method, reverse: reverse)

          let updated = try doc.render()
          try file.write(updated)
        } catch {
          fputs("error: \(file): \(error.localizedDescription)\n", stderr)
          hasErrors = true
          continue
        }
      }

      if hasErrors { throw ExitCode.failure }
    }
  }
}

extension MarkdownDocument.SortMethod: ExpressibleByArgument {}
