//
//  ConfigCommands.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry {
  /// Project configuration commands.
  struct ConfigCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "config",
      abstract: "Commands for md-utils project configuration",
      subcommands: [Schema.self]
    )
  }
}
