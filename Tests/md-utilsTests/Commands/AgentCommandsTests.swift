//
//  AgentCommandsTests.swift
//  md-utilsTests
//

import Foundation
import Testing
@testable import md_utils

@Suite("Agent Commands Tests")
struct AgentCommandsTests {

  @Test("agents subcommand group has correct configuration")
  func agentCommandsConfiguration() {
    let config = CLIEntry.AgentCommands.configuration
    #expect(config.commandName == "agents")
    #expect(config.subcommands.count == 2)
    #expect(config.subcommands[0] is CLIEntry.AgentCommands.AgentSkill.Type)
    #expect(config.subcommands[1] is CLIEntry.AgentCommands.AgentInstall.Type)
  }

  @Test("Resources/SKILL.md matches canonical SKILL.md")
  func skillMDFilesAreInSync() throws {
    let testFile = URL(filePath: #filePath)
    let repoRoot = testFile
      .deletingLastPathComponent() // Commands/
      .deletingLastPathComponent() // md-utilsTests/
      .deletingLastPathComponent() // Tests/
      .deletingLastPathComponent() // repo root

    let canonicalURL = repoRoot.appending(path: "skill/markdown-utilities/skills/markdown-utilities/SKILL.md")
    let bundledURL = repoRoot.appending(path: "Sources/md-utils/Resources/SKILL.md")

    let canonical = try String(contentsOf: canonicalURL, encoding: .utf8)
    let bundled = try String(contentsOf: bundledURL, encoding: .utf8)

    #expect(
      canonical == bundled,
      """
      Sources/md-utils/Resources/SKILL.md is out of sync with the canonical SKILL.md.
      To fix, run:
        cp skill/markdown-utilities/skills/markdown-utilities/SKILL.md \\
           Sources/md-utils/Resources/SKILL.md
      Then commit both files.
      """
    )
  }
}
