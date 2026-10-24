//
//  AgentInstall.swift
//  md-utils
//

import ArgumentParser
/// Adds Markdown document behavior to ``CLIEntry.AgentCommands``.
extension CLIEntry.AgentCommands {
  /// Defines the `AgentInstall` command behavior.
  struct AgentInstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "install",
      abstract: "Print installation instructions for the complete markdown-utilities skill",
    )
    /// Runs the command using the parsed command-line arguments.
    mutating func run() async throws {
      print("""
        markdown-utilities Skill — Installation Instructions

        CLAUDE CODE
          1. mkdir -p ~/.claude/skills/
          2. md-utils agents skill --output-directory ~/.claude/skills/markdown-utilities/
          3. Restart Claude Code or reload skills.

        CLAUDE.AI (Project Knowledge)
          1. Export: md-utils agents skill --output-directory ./markdown-utilities/
          2. Upload SKILL.md and the relevant references/*.md to project knowledge.
          3. If folder links are unavailable, load references by their filenames.

        OTHER AI ASSISTANTS
          Export the complete folder to your assistant's skill directory.
          The destination must not exist; create its parent directory first.
          To update, export to a fresh directory and review before replacing an installation.
          `md-utils agents skill` without options prints only the entrypoint.
        """)
    }
  }
}
