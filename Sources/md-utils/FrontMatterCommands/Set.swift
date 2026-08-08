//
//  Set.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
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
          let content: String = try file.read()
          guard let syntax = FrontMatterFileSyntax.resolve(
            for: file,
            includeNonMarkdown: includeNonMD
          ) else {
            throw ValidationError("No frontmatter syntax mapping for extension \"\(file.extension ?? "")\"")
          }
          let parsed = try ParsedFrontMatterFile.parse(source: content, syntax: syntax)

          if let secondLine = parsed.additionalOpeningLines.first {
            throw FrontMatterCommandError(
              message: "multiple frontmatter blocks; additional block opens at line \(secondLine)"
            )
          }

          if case .wrapped(let wrapper) = syntax, parsed.wrappedBlock == nil,
            createFrontmatter == false
          {
            let isSingleExplicitFile = options.paths.count == 1 && options.paths[0].isFile
            if isSingleExplicitFile {
              CLIStyle.writeStderr(
                "Create wrapped frontmatter using \(wrapper.name) (\(wrapper.openingWrapper) … \(wrapper.closingWrapper))? [y/N]"
              )
              let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
              guard response == "y" || response == "yes" else {
                throw FrontMatterCommandError(message: "frontmatter creation declined")
              }
            } else {
              throw FrontMatterCommandError(
                message: "missing non-Markdown frontmatter requires --create-frontmatter"
              )
            }
          }

          var doc = parsed.document

          doc.setValue(value, forKey: key)

          let updated = try parsed.rendering(doc)
          try FrontMatterFileWriter.write(updated, to: file, expectedSource: content)
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
