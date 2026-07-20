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
      abstract: "Initialize md-utils project configuration"
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
