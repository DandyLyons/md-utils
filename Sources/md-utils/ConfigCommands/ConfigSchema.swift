//
//  ConfigSchema.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry.ConfigCommands {
  struct Schema: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "schema",
      abstract: "Print the md-utils.json JSON Schema"
    )

    mutating func run() async throws {
      try ConfigSchemaPrinter.printSchema()
    }
  }
}
