//
//  AgentInstall.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry.AgentCommands {
  struct AgentInstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "install",
      abstract: "Print installation instructions for the markdown-utilities skill"
    )

    mutating func run() async throws {
      print("""
        markdown-utilities Skill — Installation Instructions

        CLAUDE CODE
          1. mkdir -p ~/.claude/skills/markdown-utilities
          2. md-utils agents skill > ~/.claude/skills/markdown-utilities/SKILL.md
          3. Restart Claude Code or reload skills.

        CLAUDE.AI (Project Knowledge)
          1. Run: md-utils agents skill
          2. Paste the output into your project's knowledge base.

        OTHER AI ASSISTANTS
          Run `md-utils agents skill` and follow your assistant's skill loading instructions.
        """)
    }
  }
}
