//
//  CLIEntryTests.swift
//  md-utilsTests
//

import Testing
@testable import md_utils

@Suite("CLI Entry Point Tests")
struct CLIEntryTests {

  @Test
  func `CLI configuration is properly set`() async throws {
    let config = CLIEntry.configuration

    #expect(config.commandName == "md-utils")
    #expect(config.version == "0.1.0-alpha")
    #expect(config.subcommands.count == 2)

    // Verify the subcommands
    #expect(config.subcommands[0] is CLIEntry.GenerateTOC.Type)
    #expect(config.subcommands[1] is CLIEntry.FrontMatterCommands.Type)
  }
}
