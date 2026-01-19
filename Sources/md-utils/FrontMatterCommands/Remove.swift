//
//  Remove.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.FrontMatterCommands {
  /// Remove a frontmatter key
  struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "remove",
      abstract: "Remove a frontmatter key",
      discussion: """
        Removes a specified key from the frontmatter.

        The operation is idempotent - removing a non-existent key is a no-op.
        The operation is silent on success (no output).
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "The frontmatter key to remove")
    var key: String

    mutating func run() async throws {
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      for file in files {
        let content: String = try file.read()
        var doc = try MarkdownDocument(content: content)

        doc.removeValue(forKey: key)

        let updated = try doc.render()
        try file.write(updated)
      }
    }
  }
}
