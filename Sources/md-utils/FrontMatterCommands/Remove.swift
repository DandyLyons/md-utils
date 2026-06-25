//
//  Remove.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
/// Adds Markdown document behavior to ``CLIEntry.FrontMatterCommands``.
///
/// See <doc:FrontmatterCommands> for workflow details.
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
        """,
      aliases: ["rm"]
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "The frontmatter key to remove")
    var key: String
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
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

          doc.removeValue(forKey: key)

          let updated = try doc.render()
          try file.write(updated)
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
