//
//  ConfigCommandsTests.swift
//  md-utilsTests
//

import Foundation
import Testing
@testable import md_utils

@Suite("config commands")
struct ConfigCommandsTests {
  @Test
  func `config command group has correct configuration`() {
    let config = CLIEntry.ConfigCommands.configuration

    #expect(config.commandName == "config")
    #expect(config.subcommands.count == 1)
    #expect(config.subcommands[0] is CLIEntry.ConfigCommands.Schema.Type)
  }

  @Test
  func `config schema parses`() throws {
    let parsed = try CLIEntry.parseAsRoot(["config", "schema"])

    #expect(parsed is CLIEntry.ConfigCommands.Schema)
  }

  @Test
  func `config schema printer returns bundled schema`() throws {
    let testFile = URL(filePath: #filePath)
    let repoRoot = testFile
      .deletingLastPathComponent() // Commands/
      .deletingLastPathComponent() // md-utilsTests/
      .deletingLastPathComponent() // Tests/
      .deletingLastPathComponent() // repo root

    let bundledURL = repoRoot.appending(path: "Sources/md-utils/Resources/md-utils.schema.json")
    let expected = try String(contentsOf: bundledURL, encoding: .utf8)

    #expect(try ConfigSchemaPrinter.content() == expected)
  }
}
