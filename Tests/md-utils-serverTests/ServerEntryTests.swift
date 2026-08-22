import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import PathKit
import Testing
import Yams
@testable import md_utils_server

@Suite("md-utils-server command line")
struct ServerEntryTests {
  @Test
  func `Serve remains the default subcommand`() throws {
    let parsed = try ServerEntry.parseAsRoot(["--port", "9090"])
    let command = try #require(parsed as? ServerEntry.Serve)

    #expect(command.port == 9090)
    #expect(command.projectRoot == ".")
  }

  @Test
  func `Explicit serve command parses startup options`() throws {
    let parsed = try ServerEntry.parseAsRoot([
      "serve", "--project-root", "example/", "--config", "custom/server.yaml",
      "--hostname", "0.0.0.0", "--port", "8081",
    ])
    let command = try #require(parsed as? ServerEntry.Serve)

    #expect(command.projectRoot == "example/")
    #expect(command.config == "custom/server.yaml")
    #expect(command.hostname == "0.0.0.0")
    #expect(command.port == 8081)
  }

  @Test
  func `Init and schema subcommands parse`() throws {
    let initialized = try ServerEntry.parseAsRoot([
      "init", "--project-root", "example/",
    ])
    let initCommand = try #require(initialized as? ServerEntry.Init)
    #expect(initCommand.projectRoot.string == "example/")

    let schema = try ServerEntry.parseAsRoot(["schema"])
    #expect(schema is ServerEntry.Schema)
  }

  @Test
  func `OpenAPI command exports equivalent JSON and YAML without records`() throws {
    let root = Path("tmp/server-openapi-command-tests/\(UUID().uuidString)/").absolute()
    defer { try? root.delete() }
    try (root + ".md-utils/server/").mkpath()
    try (root + ".md-utils/server/server.yaml").write(
      """
      serverConfigVersion: "1"
      resources: []
      """
    )
    let jsonPath = root + "contract.json"
    let yamlPath = root + "contract.yaml"

    var jsonCommand = try #require(try ServerEntry.parseAsRoot([
      "openapi", "--project-root", root.string, "--format", "json",
      "--output", jsonPath.string,
    ]) as? ServerEntry.OpenAPIExport)
    try jsonCommand.run()
    var yamlCommand = try #require(try ServerEntry.parseAsRoot([
      "openapi", "--project-root", root.string, "--format", "yaml",
      "--output", yamlPath.string,
    ]) as? ServerEntry.OpenAPIExport)
    try yamlCommand.run()

    let json = try JSONDecoder().decode(JSONValue.self, from: jsonPath.read())
    let yaml = try YAMLDecoder().decode(JSONValue.self, from: yamlPath.read())
    #expect(json == yaml)
    #expect(json.objectValue?["openapi"]?.stringValue == "3.1.1")
  }
}
