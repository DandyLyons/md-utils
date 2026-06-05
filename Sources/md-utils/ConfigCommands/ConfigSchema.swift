//
//  ConfigSchema.swift
//  md-utils
//

import ArgumentParser
/// Adds Markdown document behavior to ``CLIEntry.ConfigCommands``.
extension CLIEntry.ConfigCommands {
  /// Defines the `ConfigSchema` command behavior.
  struct Schema: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "schema",
      abstract: "Print the md-utils.json JSON Schema"
    )
    /// Runs the command using the parsed command-line arguments.
    mutating func run() async throws {
      try ConfigSchemaPrinter.printSchema()
    }
  }
}
