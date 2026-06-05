//
//  PrintConfigSchema.swift
//  md-utils
//

import ArgumentParser
/// Adds Markdown document behavior to ``CLIEntry.AgentCommands``.
extension CLIEntry.AgentCommands {
  /// Defines the `PrintConfigSchema` command behavior.
  struct PrintConfigSchema: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "printConfigSchema",
      abstract: "Print the md-utils.json JSON Schema"
    )
    /// Runs the command using the parsed command-line arguments.
    mutating func run() async throws {
      try ConfigSchemaPrinter.printSchema()
    }
  }
}
