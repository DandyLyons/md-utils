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
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Sets or updates a frontmatter key with the specified value.

        Creates the key if it doesn't exist, or updates the value if it does.
        If the document has no frontmatter, it will be added.

        On success, timing/status output is written to stderr.
        """)
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "The frontmatter key")
    var key: String

    @Option(name: .long, help: "The value to set")
    var value: String

    @Option(name: .long, help: "Frontmatter format to create or convert to (yaml, toml)")
    var frontmatterFormat: FrontMatterFormat?

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false

    @Flag(name: .long, help: "Authorize creation of wrapped frontmatter in non-Markdown files")
    var createFrontmatter = false
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      let timer = CommandTimer()
      let files = try options.resolvedFrontMatterPaths(includeNonMarkdown: includeNonMD)

      guard !files.isEmpty else {
        throw ValidationError("No frontmatter files found to process")
      }

      var hasErrors = false
      var updatedCount = 0

      for file in files {
        do {
          let parsed = try FrontMatterCLIMutator.parsedFile(
            at: file,
            includeNonMarkdown: includeNonMD
          )
          try FrontMatterCLIMutator.authorizeCreationIfNeeded(
            for: parsed,
            options: options,
            createFrontmatter: createFrontmatter
          )

          var doc = parsed.document
          if let frontmatterFormat { doc.frontMatterFormat = frontmatterFormat }

          doc.setValue(value, forKey: key)

          try FrontMatterCLIMutator.write(doc, parsed: parsed, to: file)
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
