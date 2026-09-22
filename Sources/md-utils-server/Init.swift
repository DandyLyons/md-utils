import ArgumentParser
import MarkdownUtilitiesServer
import PathKit

extension ServerEntry {
  /// Initializes the YAML and JSON Schema used by the native server.
  struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "init",
      abstract: "Initialize md-utils-server configuration"
    )

    @Option(
      name: .long,
      help: "Project directory in which to create .md-utils/server/server.yaml.",
      completion: .directory,
      transform: { Path($0) }
    )
    var projectRoot: Path = .current

    @Option(name: .long, help: "Server configuration schema version: 1, 2, or 3.")
    var schemaVersion = "1"

    mutating func run() async throws {
      guard ["1", "2", "3"].contains(schemaVersion) else { throw ValidationError("schema-version must be 1, 2, or 3") }
      let result = try MarkdownServerConfigurationBootstrapper.initialize(
        projectRoot: projectRoot,
        schemaVersion: schemaVersion,
      )
      let action = result.configurationCreated
        ? "Initialized server configuration"
        : "Server configuration already initialized"
      print(action)
      print("Config: \(result.configurationFile.string)")
      print("Schema: \(result.schemaFile.string)")
    }
  }
}
