//
//  ConfigCommandsTests.swift
//  md-utilsTests
//

import Foundation
import PathKit
import Testing
@testable import md_utils

@Suite("config commands", .serialized)
struct ConfigCommandsTests {
  @Test
  func `config command group has correct configuration`() {
    let config = CLIEntry.ConfigCommands.configuration

    #expect(config.commandName == "config")
    #expect(config.subcommands.count == 3)
    #expect(config.subcommands[0] is CLIEntry.ConfigCommands.Schema.Type)
    #expect(config.subcommands[1] is CLIEntry.ConfigCommands.Info.Type)
    #expect(config.subcommands[2] is CLIEntry.ConfigCommands.Migrate.Type)
  }

  @Test
  func `config schema parses`() throws {
    let parsed = try CLIEntry.parseAsRoot(["config", "schema"])

    #expect(parsed is CLIEntry.ConfigCommands.Schema)
  }

  @Test
  func `config schema printer returns bundled schema`() throws {
    let bundledURL = repoRoot().appending(path: "Sources/md-utils/Resources/0.2.0_md-utils.schema.json")
    let expected = try String(contentsOf: bundledURL, encoding: .utf8)

    #expect(try ConfigSchemaPrinter.content() == expected)
  }

  @Test
  func `config info parses`() throws {
    let parsed = try CLIEntry.parseAsRoot(["config", "info"])
    let command = try #require(parsed as? CLIEntry.ConfigCommands.Info)

    #expect(command.format == .text)
  }

  @Test
  func `config info parses json format`() throws {
    let parsed = try CLIEntry.parseAsRoot(["config", "info", "--format", "json"])
    let command = try #require(parsed as? CLIEntry.ConfigCommands.Info)

    #expect(command.format == .json)
  }

  @Test
  func `config migrate parses target version`() throws {
    let parsed = try CLIEntry.parseAsRoot(["config", "migrate", "--to", "0.2.0"])
    let command = try #require(parsed as? CLIEntry.ConfigCommands.Migrate)

    #expect(command.to == "0.2.0")
    #expect(command.from == nil)
    #expect(command.config == ".md-utils/md-utils.json")
    #expect(!command.dryRun)
    #expect(command.format == .text)
  }

  @Test
  func `config migrate parses all options`() throws {
    let parsed = try CLIEntry.parseAsRoot([
      "config", "migrate", "--from", "0.1.0", "--to", "0.2.0", "--config", "custom.json", "--dry-run", "--format", "json",
    ])
    let command = try #require(parsed as? CLIEntry.ConfigCommands.Migrate)

    #expect(command.from == "0.1.0")
    #expect(command.to == "0.2.0")
    #expect(command.config == "custom.json")
    #expect(command.dryRun)
    #expect(command.format == .json)
  }

  @Test
  func `config migrate rewrites legacy config as current config`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeLegacyConfig(project)
    let configPath = project + ".md-utils/md-utils.json"

    let result = try ConfigMigrator.migrate(configPath: configPath, to: "0.2.0")

    #expect(result.changed)
    #expect(result.from == "0.1.0")
    #expect(result.to == "0.2.0")
    #expect(result.updatedSchemaReference)
    #expect(result.updatedLocalSchema)

    let data = try Data(contentsOf: URL(fileURLWithPath: configPath.string))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["configVersion"] as? String == "0.2.0")
    #expect(object["$schema"] as? String == "https://dandylyons.github.io/md-utils/schemas/0.2.0/md-utils.schema.json")
    #expect(object["schemaRules"] == nil)
    let rules = try #require(object["rules"] as? [[String: Any]])
    let rule = try #require(rules.first)
    #expect(rule["schema"] == nil)
    let checks = try #require(rule["checks"] as? [[String: Any]])
    let check = try #require(checks.first)
    #expect(check["type"] as? String == "frontmatterSchema")
    #expect(check["schema"] as? String == "book.schema.json")
    #expect(check["frontmatterRequired"] as? Bool == true)

    let localSchema = try String(contentsOf: URL(fileURLWithPath: (project + ".md-utils/md-utils.schema.json").string), encoding: .utf8)
    let expectedSchema = try ConfigSchemaRegistry.schemaContent(for: "0.2.0")
    #expect(localSchema == expectedSchema)
  }

  @Test
  func `config migrate treats unversioned config as legacy`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeLegacyConfig(project, includeConfigVersion: false)
    let configPath = project + ".md-utils/md-utils.json"

    let result = try ConfigMigrator.migrate(configPath: configPath, to: "0.2.0")

    #expect(result.from == "0.1.0")
    #expect(result.changed)
    #expect(try MdUtilsConfig.load(from: configPath).configVersion == "0.2.0")
  }

  @Test
  func `config migrate dry run does not write files`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeLegacyConfig(project)
    let configPath = project + ".md-utils/md-utils.json"
    let original = try configPath.read(.utf8)

    let result = try ConfigMigrator.migrate(configPath: configPath, to: "0.2.0", dryRun: true)

    #expect(result.changed)
    #expect(result.dryRun)
    #expect(try configPath.read(.utf8) == original)
  }

  @Test
  func `config migrate validates explicit source version`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeLegacyConfig(project)
    let configPath = project + ".md-utils/md-utils.json"

    do {
      _ = try ConfigMigrator.migrate(configPath: configPath, from: "0.2.0", to: "0.2.0")
      Issue.record("Expected source version mismatch to throw")
    } catch {
      #expect(String(describing: error).contains("Expected source configVersion \"0.2.0\", found \"0.1.0\""))
    }
  }

  @Test
  func `config migrate same version is no op`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeCurrentConfig(project)
    let configPath = project + ".md-utils/md-utils.json"

    let result = try ConfigMigrator.migrate(configPath: configPath, to: "0.2.0")

    #expect(!result.changed)
    #expect(!result.updatedSchemaReference)
    #expect(!result.updatedLocalSchema)
  }

  @Test
  func `config migrate json output renders result`() throws {
    let result = ConfigMigrationResult(
      configPath: ".md-utils/md-utils.json",
      from: "0.1.0",
      to: "0.2.0",
      changed: true,
      dryRun: true,
      updatedSchemaReference: true,
      updatedLocalSchema: true
    )

    let data = try #require(try ConfigMigrateFormatter.renderJSON(result).data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["configPath"] as? String == ".md-utils/md-utils.json")
    #expect(object["from"] as? String == "0.1.0")
    #expect(object["to"] as? String == "0.2.0")
    #expect(object["changed"] as? Bool == true)
    #expect(object["dryRun"] as? Bool == true)
  }

  @Test
  func `config info text output reports supported versions and CLI version`() {
    let output = ConfigInfoFormatter.renderText()

    #expect(output.contains("You are using md-utils CLI version 0.1.0-alpha"))
    #expect(output.contains("Supported md-utils config schema versions:"))
    #expect(output.contains("  0.2.0\n  0.1.0"))
    #expect(output.contains("Default generated config schema version: 0.2.0"))
  }

  @Test
  func `config info json output reports supported versions and CLI version`() throws {
    let data = try #require(try ConfigInfoFormatter.renderJSON().data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["cliVersion"] as? String == "0.1.0-alpha")
    #expect(object["defaultConfigVersion"] as? String == "0.2.0")
    #expect(object["supportedConfigVersions"] as? [String] == ["0.1.0", "0.2.0"])
  }

  @Test
  func `public schema copies match bundled schema`() throws {
    let root = repoRoot()
    let bundledURL = root.appending(path: "Sources/md-utils/Resources/0.2.0_md-utils.schema.json")
    let versionedURL = root.appending(path: "site/schemas/0.2.0/md-utils.schema.json")
    let namedVersionedURL = root.appending(path: "site/schemas/0.2.0/md-utils-0.2.0.schema.json")
    let bundled = try String(contentsOf: bundledURL, encoding: .utf8)

    #expect(try String(contentsOf: versionedURL, encoding: .utf8) == bundled)
    #expect(try String(contentsOf: namedVersionedURL, encoding: .utf8) == bundled)
  }

  @Test
  func `bundled schema id uses immutable versioned public URL`() throws {
    let bundledURL = repoRoot().appending(path: "Sources/md-utils/Resources/0.2.0_md-utils.schema.json")
    let data = try Data(contentsOf: bundledURL)
    let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(schema?["$id"] as? String == "https://dandylyons.github.io/md-utils/schemas/0.2.0/md-utils.schema.json")
  }

  @Test
  func `bundled schema requires current config version for IDE validation`() throws {
    let bundledURL = repoRoot().appending(path: "Sources/md-utils/Resources/0.2.0_md-utils.schema.json")
    let data = try Data(contentsOf: bundledURL)
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    let configVersion = try #require(properties["configVersion"] as? [String: Any])

    #expect(configVersion["enum"] as? [String] == ["0.2.0"])
    #expect(schema["required"] as? [String] == ["configVersion", "schemaDirectory", "rules"])
  }

  private func repoRoot() -> URL {
    let testFile = URL(filePath: #filePath)
    return testFile
      .deletingLastPathComponent() // Commands/
      .deletingLastPathComponent() // md-utilsTests/
      .deletingLastPathComponent() // Tests/
      .deletingLastPathComponent() // repo root
  }

  private func createTempProject() throws -> Path {
    let path = Path(NSTemporaryDirectory()) + "md-utils-config-tests-\(UUID().uuidString)"
    try path.mkpath()
    return path
  }

  private func writeLegacyConfig(_ project: Path, includeConfigVersion: Bool = true) throws {
    let mdUtils = project + ".md-utils"
    try (mdUtils + "schemas").mkpath()
    let versionLine = includeConfigVersion ? "\n  \"configVersion\": \"0.1.0\"," : ""
    try (mdUtils + "md-utils.json").write("""
      {
        "$schema": "https://dandylyons.github.io/md-utils/schemas/0.1.0/md-utils.schema.json",
      \(versionLine)
        "schemaDirectory": ".md-utils/schemas/",
        "schemaRules": [
          {
            "name": "books",
            "schema": "book.schema.json",
            "frontmatterRequired": true,
            "match": {
              "paths": ["Books/**/*.md"],
              "frontmatter": {
                "tags": { "includes": "Book" }
              }
            }
          }
        ]
      }
      """)
    try (mdUtils + "md-utils.schema.json").write(try ConfigSchemaRegistry.schemaContent(for: "0.1.0"))
  }

  private func writeCurrentConfig(_ project: Path) throws {
    let mdUtils = project + ".md-utils"
    try (mdUtils + "schemas").mkpath()
    try MdUtilsConfig(schemaRules: [
      Rule(name: "books", schema: "book.schema.json", match: RuleMatch(paths: ["Books/**/*.md"])),
    ]).save(to: mdUtils + "md-utils.json")
  }
}
