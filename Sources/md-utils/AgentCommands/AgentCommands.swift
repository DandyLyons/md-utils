//
//  AgentCommands.swift
//  md-utils
//

import ArgumentParser
/// Adds command implementations to ``CLIEntry``.
extension CLIEntry {
  /// Defines the `Agent commands` command behavior.
  struct AgentCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "agents",
      abstract: "Commands for AI agent integration",
      subcommands: [AgentSkill.self, AgentInstall.self, PrintConfigSchema.self]
    )
  }
}
