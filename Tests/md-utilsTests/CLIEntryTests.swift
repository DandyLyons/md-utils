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
    #expect(config.subcommands.count == 1)

    // Verify the first subcommand is GenerateTOC
    let subcommand = config.subcommands[0]
    #expect(subcommand is CLIEntry.GenerateTOC.Type)
  }
}
