import Foundation
import PathKit

/// The result of initializing server configuration in an md-utils project.
public struct MarkdownServerConfigurationInitializationResult: Equatable {
  /// The canonical server configuration path.
  public let configurationFile: Path
  /// The local JSON Schema path installed for editor integration.
  public let schemaFile: Path
  /// Whether initialization created a new server configuration.
  public let configurationCreated: Bool

  /// Creates an initialization result.
  public init(configurationFile: Path, schemaFile: Path, configurationCreated: Bool) {
    self.configurationFile = configurationFile
    self.schemaFile = schemaFile
    self.configurationCreated = configurationCreated
  }
}

/// Access to the canonical JSON Schema bundled with the server library.
public enum MarkdownServerConfigurationSchema {
  /// Filename used for the project-local schema copy.
  public static let projectFileName = "server.schema.json"

  /// Returns the complete bundled JSON Schema.
  public static func content() throws -> String {
    guard let url = Bundle.module.url(
      forResource: "1_server.schema",
      withExtension: "json"
    ) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try String(contentsOf: url, encoding: .utf8)
  }
}

/// Creates the minimal files required to configure `md-utils-server`.
public enum MarkdownServerConfigurationBootstrapper {
  /// Creates `.md-utils/server/server.yaml` when absent and refreshes its local JSON Schema.
  ///
  /// Existing server configuration is never overwritten.
  public static func initialize(
    projectRoot: Path = .current
  ) throws -> MarkdownServerConfigurationInitializationResult {
    let root = projectRoot.absolute().normalize()
    let configurationDirectory = root + ".md-utils/server/"
    let configurationFile = configurationDirectory + "server.yaml"
    let schemaFile = configurationDirectory + MarkdownServerConfigurationSchema.projectFileName

    try configurationDirectory.mkpath()
    try schemaFile.write(try MarkdownServerConfigurationSchema.content())

    let configurationCreated = configurationFile.exists == false
    if configurationCreated {
      try configurationFile.write(
        """
        # yaml-language-server: $schema=server.schema.json
        serverConfigVersion: "1"
        resources: []

        """
      )
    }

    return MarkdownServerConfigurationInitializationResult(
      configurationFile: configurationFile,
      schemaFile: schemaFile,
      configurationCreated: configurationCreated
    )
  }
}
