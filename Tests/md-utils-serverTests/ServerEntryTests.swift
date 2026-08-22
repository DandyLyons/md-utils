import ArgumentParser
import Testing
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
}
