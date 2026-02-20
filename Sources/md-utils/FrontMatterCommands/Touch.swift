//
//  Touch.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.FrontMatterCommands {
  /// Add frontmatter keys without values
  struct Touch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "touch",
      abstract: "Add frontmatter keys without values",
      discussion: """
        Adds one or more keys to the frontmatter with null values.

        Keys are specified as a comma-separated list via --keys.
        If a key already exists, it is left unchanged (idempotent).
        If the document has no frontmatter, it will be created.

        The operation is silent on success (no output).

        Examples:
          md-utils fm touch --keys=title,author file.md
          md-utils fm touch --keys=draft,published ./posts/
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Comma-separated list of frontmatter keys to add"
    )
    var keys: String

    mutating func run() async throws {
      // Parse comma-separated keys
      let keyList = keys
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

      guard !keyList.isEmpty else {
        throw ValidationError("At least one key must be specified")
      }

      let files = try options.resolvedPaths()
      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      // Process each file
      var hasErrors = false

      for file in files {
        do {
          let content: String = try file.read()
          var doc = try MarkdownDocument(content: content)

          // Add each key if it doesn't exist
          for key in keyList {
            if !doc.hasKey(key) {
              try doc.createNewKeyWithNullValue(key)
            }
          }

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
