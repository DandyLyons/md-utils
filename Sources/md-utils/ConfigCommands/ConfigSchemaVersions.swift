//
//  ConfigSchemaVersions.swift
//  md-utils
//

import ArgumentParser

/// Adds config schema version reporting to ``CLIEntry.ConfigCommands``.
extension CLIEntry.ConfigCommands {
  /// Prints config schema versions supported by this CLI build.
  struct SchemaVersions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "schema-versions",
      abstract: "Print supported md-utils config schema versions"
    )

    @Option(name: .long, help: "Output format: text or json")
    var format: ConfigSchemaVersionsFormat = .text

    mutating func run() async throws {
      switch format {
      case .text:
        print(ConfigSchemaVersionsFormatter.renderText())
      case .json:
        print(try ConfigSchemaVersionsFormatter.renderJSON(), terminator: "")
      }
    }
  }
}

enum ConfigSchemaVersionsFormat: String, ExpressibleByArgument {
  case text
  case json
}
