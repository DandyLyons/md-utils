//
//  Remove.swift
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
  /// Remove a frontmatter key
  struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "remove",
      abstract: "Remove a frontmatter key",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Removes a specified key from the frontmatter.

        The operation is idempotent - removing a non-existent key is a no-op.
        The operation is silent on success (no output).
        """),
      aliases: ["rm"]
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "The frontmatter key to remove")
    var key: String

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      let files = try options.resolvedFrontMatterPaths(includeNonMarkdown: includeNonMD)

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false

      for file in files {
        do {
          let parsed = try FrontMatterCLIMutator.parsedFile(
            at: file,
            includeNonMarkdown: includeNonMD
          )
          var doc = parsed.document
          guard doc.hasKey(key) else { continue }

          doc.removeValue(forKey: key)

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
