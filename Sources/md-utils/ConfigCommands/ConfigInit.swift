//
//  ConfigInit.swift
//  md-utils
//

import ArgumentParser
import PathKit

extension CLIEntry.ConfigCommands {
  /// Initializes md-utils project configuration without creating rules or types.
  struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "init",
      abstract: "Initialize md-utils project configuration",
      discussion: "Creates .md-utils/ with default config schema 0.2.0 and empty schemas/, types/ and rules/ directories. Preserves existing configuration. It does not add a rule or type. --root defaults to the current directory; parent directories are not searched.",
    )

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    mutating func run() async throws {
      let result = try RulesConfigBootstrapper.ensureProjectFiles(root: root)
      let action = result.configCreated ? "Initialized configuration" : "Configuration already initialized"
      print(CLIStyle.success(action))
      print("\(CLIStyle.metadata("Config:")) \(CLIStyle.path(result.configFile.string))")
      print("\(CLIStyle.metadata("Schema:")) \(CLIStyle.path(result.configSchemaFile.string))")
    }
  }
}
