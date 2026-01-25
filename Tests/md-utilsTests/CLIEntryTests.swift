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
    #expect(config.subcommands.count == 8)

    // Verify the subcommands are registered (in order as listed in CLIEntry)
    #expect(config.subcommands[0] is CLIEntry.Body.Type)
    #expect(config.subcommands[1] is CLIEntry.ConvertCommands.Type)
    #expect(config.subcommands[2] is CLIEntry.ExtractSection.Type)
    #expect(config.subcommands[3] is CLIEntry.FileMetadataCommands.Type)
    #expect(config.subcommands[4] is CLIEntry.FrontMatterCommands.Type)
    #expect(config.subcommands[5] is CLIEntry.GenerateTOC.Type)
    #expect(config.subcommands[6] is CLIEntry.HeadingCommands.Type)
    #expect(config.subcommands[7] is CLIEntry.Lines.Type)
  }
}
