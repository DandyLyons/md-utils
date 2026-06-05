//
//  AgentSkill.swift
//  md-utils
//

import ArgumentParser
import Foundation
/// Adds Markdown document behavior to ``CLIEntry.AgentCommands``.
extension CLIEntry.AgentCommands {
  /// Defines the `AgentSkill` command behavior.
  struct AgentSkill: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "skill",
      abstract: "Print the markdown-utilities skill content"
    )
    /// Runs the command using the parsed command-line arguments.
    mutating func run() async throws {
      guard let url = Bundle.module.url(forResource: "SKILL", withExtension: "md") else {
        throw ValidationError("SKILL.md not found in bundle.")
      }
      let content = try String(contentsOf: url, encoding: .utf8)
      print(content, terminator: "")
    }
  }
}
