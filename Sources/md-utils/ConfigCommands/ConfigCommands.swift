//
//  ConfigCommands.swift
//  md-utils
//

import ArgumentParser
/// Adds command implementations to ``CLIEntry``.
extension CLIEntry {
  /// Project configuration commands.
  struct ConfigCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "config",
      abstract: "Commands for md-utils project configuration",
      subcommands: [Schema.self, Info.self, Migrate.self]
    )
  }
}
