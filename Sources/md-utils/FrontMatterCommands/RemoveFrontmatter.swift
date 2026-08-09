//
//  RemoveFrontmatter.swift
//  md-utils
//

import ArgumentParser
import Foundation
import PathKit

/// Adds Markdown document behavior to ``CLIEntry.FrontMatterCommands``.
///
/// See <doc:FrontmatterCommands> for workflow details.
extension CLIEntry.FrontMatterCommands {
  /// Remove complete frontmatter blocks from selected files.
  struct RemoveFrontmatter: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "remove-frontmatter",
      abstract: "Remove the complete frontmatter block",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Completely removes the frontmatter delimiters and all enclosed YAML.

        You will be prompted once for each file that contains frontmatter. Enter
        exactly y to confirm removal, or use -y/--yes to skip confirmation.
        Files without frontmatter are left unchanged and do not prompt.
        """),
      aliases: ["rmfm"]
    )

    @OptionGroup var options: GlobalOptions

    @Flag(name: [.customShort("y"), .long], help: "Skip confirmation prompt")
    var yes = false

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false

    /// Runs the command using the parsed command-line arguments.
    mutating func run() async throws {
      let files = try options.resolvedFrontMatterPaths(includeNonMarkdown: includeNonMD)

      guard files.isEmpty == false else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false
      for file in files {
        do {
          try removeFrontMatter(from: file)
        } catch {
          CLIStyle.writeError("\(CLIStyle.path(file.string)): \(error.localizedDescription)")
          hasErrors = true
        }
      }

      if hasErrors { throw ExitCode.failure }
    }

    /// Removes frontmatter from one file after any required confirmation.
    private func removeFrontMatter(from path: Path) throws {
      let parsed = try FrontMatterCLIMutator.parsedFile(
        at: path,
        includeNonMarkdown: includeNonMD
      )
      guard parsed.hasFrontMatterBlock else { return }

      if yes == false {
        print(
          "Are you sure you want to remove all frontmatter from '\(CLIStyle.path(path.string))'? (y/N): ",
          terminator: ""
        )
        fflush(stdout)

        let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response == "y" else {
          print(CLIStyle.muted("Cancelled."))
          return
        }
      }

      try FrontMatterCLIMutator.removeFrontMatter(parsed: parsed, from: path)
      print("\(CLIStyle.success("✓")) Removed frontmatter from '\(CLIStyle.path(path.string))'")
    }
  }
}
