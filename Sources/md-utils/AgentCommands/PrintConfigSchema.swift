//
//  PrintConfigSchema.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry.AgentCommands {
  struct PrintConfigSchema: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "printConfigSchema",
      abstract: "Print the md-utils.json JSON Schema"
    )

    mutating func run() async throws {
      try ConfigSchemaPrinter.printSchema()
    }
  }
}
