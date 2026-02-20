//
//  Rename.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.FrontMatterCommands {
  /// Rename a frontmatter key
  struct Rename: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "rename",
      abstract: "Rename a key in frontmatter",
      discussion: """
        Renames an existing frontmatter key to a new name, preserving the value.

        The operation will fail if:
        - The old key doesn't exist
        - The new key already exists (to prevent overwriting)

        Examples:
          # Rename 'date' to 'created' in a single file
          md-utils fm rename --key date --new-key created document.md

          # Rename key across all Markdown files in a directory
          md-utils fm rename --key tags --new-key categories ./docs/
        """,
      aliases: ["rn"]
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .shortAndLong, help: "The key to rename")
    var key: String

    @Option(help: "The new key name")
    var newKey: String

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

          try doc.renameKey(from: key, to: newKey)

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
