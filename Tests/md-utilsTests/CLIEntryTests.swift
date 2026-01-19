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
    #expect(config.subcommands.count == 6)

    // Verify the subcommands are registered
    #expect(config.subcommands[0] is CLIEntry.GenerateTOC.Type)
    #expect(config.subcommands[1] is CLIEntry.FrontMatterCommands.Type)
    #expect(config.subcommands[2] is CLIEntry.ConvertCommands.Type)
    #expect(config.subcommands[3] is CLIEntry.PromoteHeading.Type)
    #expect(config.subcommands[4] is CLIEntry.DemoteHeading.Type)
    #expect(config.subcommands[5] is CLIEntry.ExtractSection.Type)
  }
}
