//
//  AgentSkill.swift
//  md-utils
//

import ArgumentParser
import Foundation

extension CLIEntry.AgentCommands {
  struct AgentSkill: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "skill",
      abstract: "Print the markdown-utilities skill content"
    )

    mutating func run() async throws {
      guard let url = Bundle.module.url(forResource: "SKILL", withExtension: "md") else {
        throw ValidationError("SKILL.md not found in bundle.")
      }
      let content = try String(contentsOf: url, encoding: .utf8)
      print(content, terminator: "")
    }
  }
}
