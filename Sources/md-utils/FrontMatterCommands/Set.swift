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

        Supply exactly one of --value (a string, including an empty string)
        or --null (a YAML null). TOML cannot represent null; use
        --frontmatter-format yaml to explicitly convert a TOML document.

        On success, timing/status output is written to stderr.
        """)
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var lineCommentOptions: LineCommentFrontMatterOptions

    @Option(name: .long, help: "The frontmatter key")
    var key: String

    @Option(name: .long, help: "The string value to set (use '' for an empty string)")
    var value: String?

    @Flag(name: .long, help: "Set a YAML null value instead of a string; mutually exclusive with --value")
    var null = false

    @Option(name: .long, help: "Frontmatter format to create or convert to (yaml, toml)")
    var frontmatterFormat: FrontMatterFormat?

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false

    @Flag(name: .long, help: "Authorize frontmatter creation in non-Markdown files")
    var createFrontmatter = false

    mutating func validate() throws {
      guard (value != nil) != null else {
        throw ValidationError("Supply exactly one of --value or --null")
      }
    }
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      let timer = CommandTimer()
      let files = try options.resolvedFrontMatterPaths(
        includeNonMarkdown: includeNonMD,
        lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
      )

      guard !files.isEmpty else {
        throw ValidationError("No frontmatter files found to process")
      }

      var hasErrors = false
      var updatedCount = 0

      for file in files {
        do {
          let parsed = try FrontMatterCLIMutator.parsedFile(
            at: file,
            includeNonMarkdown: includeNonMD,
            lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
          )
          try FrontMatterCLIMutator.authorizeCreationIfNeeded(
            for: parsed,
            options: options,
            createFrontmatter: createFrontmatter
          )

          var doc = parsed.document
          if let frontmatterFormat { doc.frontMatterFormat = frontmatterFormat }

          if null {
            guard doc.frontMatterFormat != .toml else {
              throw ValidationError("TOML cannot represent null; use --frontmatter-format yaml to convert explicitly")
            }
            doc.frontMatter[key] = .null
          } else if let value {
            doc.setValue(value, forKey: key)
          }

          try FrontMatterCLIMutator.write(doc, parsed: parsed, to: file)
          updatedCount += 1
        } catch {
          let message = (error as? ValidationError)?.description ?? error.localizedDescription
          CLIStyle.writeError("\(CLIStyle.path(file.string)): \(message)")
          hasErrors = true
          continue
        }
      }

      timer.writeStatus("Set frontmatter key \"\(key)\" in \(updatedCount) file(s)")
      if hasErrors { throw ExitCode.failure }
    }
  }
}
