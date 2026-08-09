//
//  RulesCommands.swift
//  md-utils
//

import ArgumentParser
/// Adds command implementations to ``CLIEntry``.
///
/// See <doc:RulesValidationCommands> for workflow details.
extension CLIEntry {
  /// Project-level file rules commands.
  struct RulesCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "rules",
      abstract: "Validate files with configured rules",
      subcommands: [
        Add.self,
        Remove.self,
        List.self,
        FilesMatching.self,
        Matching.self,
        Describe.self,
        Validate.self,
      ]
    )
  }
}
