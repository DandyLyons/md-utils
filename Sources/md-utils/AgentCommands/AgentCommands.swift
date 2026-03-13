//
//  AgentCommands.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry {
  struct AgentCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "agents",
      abstract: "Commands for AI agent integration",
      subcommands: [AgentSkill.self, AgentInstall.self]
    )
  }
}
