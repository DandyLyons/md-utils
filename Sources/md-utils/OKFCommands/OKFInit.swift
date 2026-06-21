//
//  OKFInit.swift
//  md-utils
//

import ArgumentParser
import PathKit

extension CLIEntry.OKFCommands {
  /// Initializes a minimal OKF v0.1 draft bundle.
  struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "init",
      abstract: "EXPERIMENTAL: Initialize an OKF v0.1 draft bundle",
      discussion: """
        Creates a minimal OKF bundle scaffold and installs md-utils schema configuration.
        Existing files are preserved. log.md is created only when --with-log is passed.

        Example: md-utils okf init ./knowledge/ --with-log
        """
    )

    @Argument(help: "Path to the OKF bundle directory; defaults to the current directory", completion: .directory, transform: { Path($0) })
    var bundlePath: Path = .current

    @Flag(name: .long, help: "Create optional log.md during initialization")
    var withLog: Bool = false

    mutating func run() async throws {
      let summary = try OKFInitializer.initialize(options: OKFInitOptions(bundlePath: bundlePath, withLog: withLog))
      print(OKFInitFormatter.render(summary))
    }
  }
}
