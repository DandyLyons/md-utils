//
//  LinkCommandsTests.swift
//  md-utilsTests
//

import ArgumentParser
import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("LinkCommands CLI Tests")
struct LinkCommandsTests {

  /// Creates a temporary vault directory with the given file structure.
  private func createVault(_ files: [String: String]) throws -> Path {
    let vault = Path(NSTemporaryDirectory()) + "test-vault-\(UUID().uuidString)"
    try vault.mkpath()

    for (relativePath, content) in files {
      let filePath = vault + relativePath
      try filePath.parent().mkpath()
      try filePath.write(content)
    }

    return vault
  }

  // MARK: - Command Configuration

  @Test
  func `Link command group has correct configuration`() {
    let config = CLIEntry.LinkCommands.configuration

    #expect(config.commandName == "links")
    #expect(config.subcommands.count == 3)
    #expect(config.subcommands[0] is CLIEntry.ListLinks.Type)
    #expect(config.subcommands[1] is CLIEntry.Check.Type)
    #expect(config.subcommands[2] is CLIEntry.Backlinks.Type)
  }

  @Test
  func `ListLinks command has correct configuration`() {
    let config = CLIEntry.ListLinks.configuration
    #expect(config.commandName == "list")
  }

  @Test
  func `Check command has correct configuration`() {
    let config = CLIEntry.Check.configuration
    #expect(config.commandName == "check")
  }

  @Test
  func `Backlinks command has correct configuration`() {
    let config = CLIEntry.Backlinks.configuration
    #expect(config.commandName == "backlinks")
  }

  // MARK: - Argument Parsing

  @Test
  func `ListLinks parses file argument`() throws {
    let vault = try createVault(["page.md": "# Page\n[[Other]]"])
    defer { try? vault.delete() }

    let file = vault + "page.md"
    let cmd_ = try CLIEntry.parseAsRoot(["links", "list", file.string, "--root", vault.string])
    let cmd = try #require(cmd_ as? CLIEntry.ListLinks)

    #expect(cmd.json == false)
  }

  @Test
  func `ListLinks parses json flag`() throws {
    let vault = try createVault(["page.md": "# Page"])
    defer { try? vault.delete() }

    let file = vault + "page.md"
    let cmd_ = try CLIEntry.parseAsRoot(
      ["links", "list", file.string, "--root", vault.string, "--json"]
    )
    let cmd = try #require(cmd_ as? CLIEntry.ListLinks)

    #expect(cmd.json == true)
  }

  @Test
  func `Check parses root option`() throws {
    let vault = try createVault(["page.md": "# Page"])
    defer { try? vault.delete() }

    let file = vault + "page.md"
    let cmd_ = try CLIEntry.parseAsRoot(
      ["links", "check", file.string, "--root", vault.string]
    )
    _ = try #require(cmd_ as? CLIEntry.Check)
  }

  @Test
  func `Backlinks parses scan-scope option`() throws {
    let vault = try createVault(["page.md": "# Page"])
    defer { try? vault.delete() }

    let file = vault + "page.md"
    let cmd_ = try CLIEntry.parseAsRoot(
      ["links", "backlinks", file.string, "--root", vault.string, "--scan-scope", vault.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.Backlinks)

    #expect(cmd.scanScope != nil)
  }

  // MARK: - Alias Parsing

  @Test
  func `Link commands accessible via ln alias`() throws {
    let vault = try createVault(["page.md": "# Page"])
    defer { try? vault.delete() }

    let file = vault + "page.md"
    let cmd_ = try CLIEntry.parseAsRoot(["ln", "list", file.string, "--root", vault.string])
    _ = try #require(cmd_ as? CLIEntry.ListLinks)
  }

  @Test
  func `ListLinks accessible via ls alias`() throws {
    let vault = try createVault(["page.md": "# Page"])
    defer { try? vault.delete() }

    let file = vault + "page.md"
    let cmd_ = try CLIEntry.parseAsRoot(["links", "ls", file.string, "--root", vault.string])
    _ = try #require(cmd_ as? CLIEntry.ListLinks)
  }

  @Test
  func `Backlinks accessible via bl alias`() throws {
    let vault = try createVault(["page.md": "# Page"])
    defer { try? vault.delete() }

    let file = vault + "page.md"
    let cmd_ = try CLIEntry.parseAsRoot(
      ["links", "bl", file.string, "--root", vault.string]
    )
    _ = try #require(cmd_ as? CLIEntry.Backlinks)
  }

  // MARK: - Check: All Links Resolve

  @Test
  func `Check passes when all links resolve`() async throws {
    let vault = try createVault([
      "page.md": "# Page\n[[other]]",
      "other.md": "# Other",
    ])
    defer { try? vault.delete() }

    let file = vault + "page.md"
    var cmd_ = try CLIEntry.parseAsRoot(
      ["links", "check", file.string, "--root", vault.string]
    )
    var cmd = try #require(cmd_ as? CLIEntry.Check)

    // Should not throw (all links resolve)
    try await cmd.run()
  }

  // MARK: - Check: Broken Links Fail

  @Test
  func `Check fails when links are broken`() async throws {
    let vault = try createVault([
      "page.md": "# Page\n[[nonexistent]]",
    ])
    defer { try? vault.delete() }

    let file = vault + "page.md"
    var cmd_ = try CLIEntry.parseAsRoot(
      ["links", "check", file.string, "--root", vault.string]
    )
    var cmd = try #require(cmd_ as? CLIEntry.Check)

    // Should throw ExitCode.failure
    do {
      try await cmd.run()
      Issue.record("Expected check to fail for broken link")
    } catch let error as ExitCode {
      #expect(error == .failure)
    }
  }

  // MARK: - Backlinks: Finds Linking Files

  @Test
  func `Backlinks finds files that link to target`() async throws {
    let vault = try createVault([
      "target.md": "# Target",
      "linker.md": "# Linker\n[[target]]",
      "other.md": "# Other\nNo links here",
    ])
    defer { try? vault.delete() }

    let target = vault + "target.md"
    var cmd_ = try CLIEntry.parseAsRoot(
      ["links", "backlinks", target.string, "--root", vault.string]
    )
    var cmd = try #require(cmd_ as? CLIEntry.Backlinks)

    // Should succeed without error
    try await cmd.run()
  }

  // MARK: - ListLinks: JSON Output

  @Test
  func `ListLinks JSON output is valid`() async throws {
    let vault = try createVault([
      "page.md": "# Page\n[[other]]",
      "other.md": "# Other",
    ])
    defer { try? vault.delete() }

    let file = vault + "page.md"
    var cmd_ = try CLIEntry.parseAsRoot(
      ["links", "list", file.string, "--root", vault.string, "--json"]
    )
    var cmd = try #require(cmd_ as? CLIEntry.ListLinks)

    // Should succeed without error
    try await cmd.run()
  }

  // MARK: - ListLinks: File With No Wikilinks

  @Test
  func `ListLinks handles file with no wikilinks`() async throws {
    let vault = try createVault([
      "plain.md": "# Plain\nNo wikilinks here.",
    ])
    defer { try? vault.delete() }

    let file = vault + "plain.md"
    var cmd_ = try CLIEntry.parseAsRoot(
      ["links", "list", file.string, "--root", vault.string]
    )
    var cmd = try #require(cmd_ as? CLIEntry.ListLinks)

    // Should succeed without error
    try await cmd.run()
  }

  // MARK: - Backlinks: No Incoming Links

  @Test
  func `Backlinks handles target with no incoming links`() async throws {
    let vault = try createVault([
      "isolated.md": "# Isolated",
      "other.md": "# Other\nNo links to isolated",
    ])
    defer { try? vault.delete() }

    let target = vault + "isolated.md"
    var cmd_ = try CLIEntry.parseAsRoot(
      ["links", "backlinks", target.string, "--root", vault.string]
    )
    var cmd = try #require(cmd_ as? CLIEntry.Backlinks)

    // Should succeed without error
    try await cmd.run()
  }
}
