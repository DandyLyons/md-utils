//
//  Touch.swift
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
  /// Add frontmatter keys without values
  struct Touch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "touch",
      abstract: "Add frontmatter keys without values",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Adds one or more keys to the frontmatter with null values.

        Keys are specified as a comma-separated list via --keys.
        If a key already exists, it is left unchanged (idempotent).
        If the document has no frontmatter, it will be created.

        The operation is silent on success (no output).

        Examples:
          md-utils fm touch --keys=title,author file.md
          md-utils fm touch --keys=draft,published ./posts/
        """)
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var lineCommentOptions: LineCommentFrontMatterOptions

    @Option(
      name: .long,
      help: "Comma-separated list of frontmatter keys to add"
    )
    var keys: String

    @Option(name: .long, help: "Frontmatter format to create or convert to (yaml, toml)")
    var frontmatterFormat: FrontMatterFormat?

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false

    @Flag(name: .long, help: "Authorize frontmatter creation in non-Markdown files")
    var createFrontmatter = false
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      // Parse comma-separated keys
      let keyList = keys
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

      guard !keyList.isEmpty else {
        throw ValidationError("At least one key must be specified")
      }

      let files = try options.resolvedFrontMatterPaths(
        includeNonMarkdown: includeNonMD,
        lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
      )
      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      // Process each file
      var hasErrors = false

      for file in files {
        do {
          let parsed = try FrontMatterCLIMutator.parsedFile(
            at: file,
            includeNonMarkdown: includeNonMD,
            lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
          )
          var doc = parsed.document
          if let frontmatterFormat { doc.frontMatterFormat = frontmatterFormat }
          let missingKeys = keyList.filter { doc.hasKey($0) == false }
          guard missingKeys.isEmpty == false else { continue }
          try FrontMatterCLIMutator.authorizeCreationIfNeeded(
            for: parsed,
            options: options,
            createFrontmatter: createFrontmatter
          )

          // Add each key if it doesn't exist
          for key in missingKeys {
            try doc.createNewKeyWithNullValue(key)
          }

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
