//
//  SchemaCommands.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry {
  /// Project-level frontmatter schema commands.
  struct SchemaCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "schema",
      abstract: "Validate Markdown frontmatter with JSON Schema",
      subcommands: [
        Init.self,
        List.self,
        Validate.self,
      ]
    )
  }
}
