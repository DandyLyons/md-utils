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

    mutating func run() async throws {
      let result = try MarkdownServerConfigurationBootstrapper.initialize(
        projectRoot: projectRoot
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
