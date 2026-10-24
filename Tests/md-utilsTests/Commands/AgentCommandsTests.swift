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
    #expect(config.subcommands.count == 3)
    #expect(config.subcommands[0] is CLIEntry.AgentCommands.AgentSkill.Type)
    #expect(config.subcommands[1] is CLIEntry.AgentCommands.AgentInstall.Type)
    #expect(config.subcommands[2] is CLIEntry.AgentCommands.PrintConfigSchema.Type)
  }

  @Test("agents printConfigSchema parses")
  func printConfigSchemaParses() throws {
    let parsed = try CLIEntry.parseAsRoot(["agents", "printConfigSchema"])

    #expect(parsed is CLIEntry.AgentCommands.PrintConfigSchema)
  }

  private var repoRoot: URL {
    let testFile = URL(filePath: #filePath)
    return testFile
      .deletingLastPathComponent() // Commands/
      .deletingLastPathComponent() // md-utilsTests/
      .deletingLastPathComponent() // Tests/
      .deletingLastPathComponent() // repo root

  }

  private func inventory(_ directory: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for path in try FileManager.default.subpathsOfDirectory(atPath: directory.path) {
      let url = directory.appending(path: path)
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      try #require(values.isSymbolicLink != true)
      if values.isRegularFile == true {
        result[path] = try Data(contentsOf: url)
      }
    }
    return result
  }

  @Test("Complete source and built skill bundles match the canonical distribution")
  func completeSkillIsInSync() throws {
    let canonical = try inventory(repoRoot.appending(path: "skill/markdown-utilities/skills/markdown-utilities"))
    try #require(canonical["SKILL.md"] != nil)
    try #require(canonical["references/rules.md"] != nil)
    let resource = try inventory(repoRoot.appending(path: "Sources/md-utils/Resources/AgentSkill"))
    let built = try inventory(CLIEntry.AgentCommands.AgentSkill.resourceDirectory())
    #expect(resource == canonical, "Run python3 scripts/sync-agent-skill.py")
    #expect(built == canonical, "Rebuild the CLI after synchronizing the complete skill")
  }

  @Test("Complete export preserves nested references and refuses an existing installation")
  func exportSkill() async throws {
    let parent = repoRoot.appending(path: "tmp/agent-export-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    let destination = parent.appending(path: "markdown-utilities")
    var command = try CLIEntry.AgentCommands.AgentSkill.parse([
      "--output-directory", destination.path,
    ])
    try await command.run()
    let expected = try inventory(repoRoot.appending(path: "skill/markdown-utilities/skills/markdown-utilities"))
    #expect(try inventory(destination) == expected)

    let customized = destination.appending(path: "SKILL.md")
    try Data("local customization".utf8).write(to: customized)
    do {
      try await command.run()
      Issue.record("Export must refuse an existing installation")
    } catch let error as CocoaError {
      #expect(error.code == .fileWriteFileExists)
    }
    #expect(try String(contentsOf: customized, encoding: .utf8) == "local customization")
  }
}
