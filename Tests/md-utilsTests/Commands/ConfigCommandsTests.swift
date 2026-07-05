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
    let bundledURL = repoRoot().appending(path: "Sources/md-utils/Resources/md-utils.schema.json")
    let expected = try String(contentsOf: bundledURL, encoding: .utf8)

    #expect(try ConfigSchemaPrinter.content() == expected)
  }

  @Test
  func `public schema copies match bundled schema`() throws {
    let root = repoRoot()
    let bundledURL = root.appending(path: "Sources/md-utils/Resources/md-utils.schema.json")
    let versionedURL = root.appending(path: "site/schemas/0.1.0/md-utils.schema.json")
    let namedVersionedURL = root.appending(path: "site/schemas/0.1.0/md-utils-0.1.0.schema.json")
    let bundled = try String(contentsOf: bundledURL, encoding: .utf8)

    #expect(try String(contentsOf: versionedURL, encoding: .utf8) == bundled)
    #expect(try String(contentsOf: namedVersionedURL, encoding: .utf8) == bundled)
  }

  @Test
  func `bundled schema id uses immutable versioned public URL`() throws {
    let bundledURL = repoRoot().appending(path: "Sources/md-utils/Resources/md-utils.schema.json")
    let data = try Data(contentsOf: bundledURL)
    let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(schema?["$id"] as? String == "https://dandylyons.github.io/md-utils/schemas/0.1.0/md-utils.schema.json")
  }

  private func repoRoot() -> URL {
    let testFile = URL(filePath: #filePath)
    return testFile
      .deletingLastPathComponent() // Commands/
      .deletingLastPathComponent() // md-utilsTests/
      .deletingLastPathComponent() // Tests/
      .deletingLastPathComponent() // repo root
  }
}
