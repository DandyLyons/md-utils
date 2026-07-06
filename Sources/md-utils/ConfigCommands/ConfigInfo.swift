//
//  ConfigInfo.swift
//  md-utils
//

import ArgumentParser

/// Adds config schema version reporting to ``CLIEntry.ConfigCommands``.
extension CLIEntry.ConfigCommands {
  /// Prints version and config information for this CLI build.
  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "info",
      abstract: "Print md-utils CLI and config information"
    )

    @Option(name: .long, help: "Output format: text or json")
    var format: ConfigInfoFormat = .text

    mutating func run() async throws {
      switch format {
      case .text:
        print(ConfigInfoFormatter.renderText())
      case .json:
        print(try ConfigInfoFormatter.renderJSON(), terminator: "")
      }
    }
  }
}

enum ConfigInfoFormat: String, ExpressibleByArgument {
  case text
  case json
}
