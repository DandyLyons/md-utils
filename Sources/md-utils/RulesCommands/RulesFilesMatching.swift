//
//  RulesFilesMatching.swift
//  md-utils
//

import ArgumentParser
import PathKit

/// Adds Markdown document behavior to ``CLIEntry.RulesCommands``.
///
/// See <doc:RulesValidationCommands> for workflow details.
extension CLIEntry.RulesCommands {
  /// Defines the `rules files-matching` command behavior.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  struct FilesMatching: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "files-matching",
      abstract: "List Markdown files matching a configured rule"
    )

    @Argument(help: "Rule name to match files against")
    var ruleName: String

    @Flag(name: .long, help: "Print absolute paths instead of project-relative paths")
    var absolute = false

    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:RulesValidationCommands> for workflow details.
    mutating func run() async throws {
      let files = try RulesValidatorRunner.filesMatching(ruleName: ruleName)
      print(RulesFilesMatchingFormatter.render(files, ruleName: ruleName, absolute: absolute))
    }
  }
}

enum RulesFilesMatchingFormatter {
  static func render(_ files: [Path], ruleName: String, root: Path = .current, absolute: Bool = false) -> String {
    guard !files.isEmpty else {
      return CLIStyle.muted("No files matched rule \"\(ruleName)\".")
    }

    return files.map { file in
      absolute ? file.absolute().string : relativePath(from: root, to: file)
    }.joined(separator: "\n")
  }
}
