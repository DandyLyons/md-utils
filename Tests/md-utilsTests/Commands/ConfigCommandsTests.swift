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
    #expect(config.subcommands.count == 2)
    #expect(config.subcommands[0] is CLIEntry.ConfigCommands.Schema.Type)
    #expect(config.subcommands[1] is CLIEntry.ConfigCommands.SchemaVersions.Type)
  }

  @Test
  func `config schema parses`() throws {
    let parsed = try CLIEntry.parseAsRoot(["config", "schema"])

    #expect(parsed is CLIEntry.ConfigCommands.Schema)
  }

  @Test
  func `config schema printer returns bundled schema`() throws {
    let bundledURL = repoRoot().appending(path: "Sources/md-utils/Resources/0.1.0_md-utils.schema.json")
    let expected = try String(contentsOf: bundledURL, encoding: .utf8)

    #expect(try ConfigSchemaPrinter.content() == expected)
  }

  @Test
  func `config schema versions parses`() throws {
    let parsed = try CLIEntry.parseAsRoot(["config", "schema-versions"])
    let command = try #require(parsed as? CLIEntry.ConfigCommands.SchemaVersions)

    #expect(command.format == .text)
  }

  @Test
  func `config schema versions parses json format`() throws {
    let parsed = try CLIEntry.parseAsRoot(["config", "schema-versions", "--format", "json"])
    let command = try #require(parsed as? CLIEntry.ConfigCommands.SchemaVersions)

    #expect(command.format == .json)
  }

  @Test
  func `config schema versions text output reports supported versions and CLI version`() {
    let output = ConfigSchemaVersionsFormatter.renderText()

    #expect(output.contains("Supported md-utils config schema versions:"))
    #expect(output.contains("  0.1.0"))
    #expect(output.contains("Default generated config schema version:"))
    #expect(output.contains("CLI version:"))
    #expect(output.contains("0.1.0-alpha"))
  }

  @Test
  func `config schema versions json output reports supported versions and CLI version`() throws {
    let data = try #require(try ConfigSchemaVersionsFormatter.renderJSON().data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["cliVersion"] as? String == "0.1.0-alpha")
    #expect(object["defaultConfigVersion"] as? String == "0.1.0")
    #expect(object["supportedConfigVersions"] as? [String] == ["0.1.0"])
  }

  @Test
  func `public schema copies match bundled schema`() throws {
    let root = repoRoot()
    let bundledURL = root.appending(path: "Sources/md-utils/Resources/0.1.0_md-utils.schema.json")
    let versionedURL = root.appending(path: "site/schemas/0.1.0/md-utils.schema.json")
    let namedVersionedURL = root.appending(path: "site/schemas/0.1.0/md-utils-0.1.0.schema.json")
    let bundled = try String(contentsOf: bundledURL, encoding: .utf8)

    #expect(try String(contentsOf: versionedURL, encoding: .utf8) == bundled)
    #expect(try String(contentsOf: namedVersionedURL, encoding: .utf8) == bundled)
  }

  @Test
  func `bundled schema id uses immutable versioned public URL`() throws {
    let bundledURL = repoRoot().appending(path: "Sources/md-utils/Resources/0.1.0_md-utils.schema.json")
    let data = try Data(contentsOf: bundledURL)
    let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(schema?["$id"] as? String == "https://dandylyons.github.io/md-utils/schemas/0.1.0/md-utils.schema.json")
  }

  @Test
  func `bundled schema requires current config version for IDE validation`() throws {
    let bundledURL = repoRoot().appending(path: "Sources/md-utils/Resources/0.1.0_md-utils.schema.json")
    let data = try Data(contentsOf: bundledURL)
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    let configVersion = try #require(properties["configVersion"] as? [String: Any])

    #expect(configVersion["enum"] as? [String] == ["0.1.0"])
    #expect(schema["required"] as? [String] == ["configVersion", "schemaDirectory", "schemaRules"])
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
