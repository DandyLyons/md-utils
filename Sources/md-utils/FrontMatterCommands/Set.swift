//
//  Set.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.FrontMatterCommands {
  /// Set or update a frontmatter value
  struct Set: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "set",
      abstract: "Set a frontmatter value",
      discussion: """
        Sets or updates a frontmatter key with the specified value.

        Creates the key if it doesn't exist, or updates the value if it does.
        If the document has no frontmatter, it will be added.

        The operation is silent on success (no output).
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "The frontmatter key")
    var key: String

    @Option(name: .long, help: "The value to set")
    var value: String

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

          if doc.containsYAMLComments {
            fputs("warning: \(file): frontmatter contains YAML comments which will be lost\n", stderr)
          }

          doc.setValue(value, forKey: key)

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
