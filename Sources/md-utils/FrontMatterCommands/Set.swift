//
//  Set.swift
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
  /// Set or update a frontmatter value
  struct Set: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "set",
      abstract: "Set a frontmatter value",
      discussion: """
        Sets or updates a frontmatter key with the specified value.

        Creates the key if it doesn't exist, or updates the value if it does.
        If the document has no frontmatter, it will be added.

        On success, timing/status output is written to stderr.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "The frontmatter key")
    var key: String

    @Option(name: .long, help: "The value to set")
    var value: String
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      let timer = CommandTimer()
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false
      var updatedCount = 0

      for file in files {
        do {
          let content: String = try file.read()
          var doc = try MarkdownDocument(content: content)

          doc.setValue(value, forKey: key)

          let updated = try doc.render()
          try file.write(updated)
          updatedCount += 1
        } catch {
          CLIStyle.writeError("\(CLIStyle.path(file.string)): \(error.localizedDescription)")
          hasErrors = true
          continue
        }
      }

      timer.writeStatus("Set frontmatter key \"\(key)\" in \(updatedCount) file(s)")
      if hasErrors { throw ExitCode.failure }
    }
  }
}
