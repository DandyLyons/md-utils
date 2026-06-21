//
//  OKFReport.swift
//  md-utils
//

import ArgumentParser
import PathKit

extension CLIEntry.OKFCommands {
  /// Reports OKF bundle inventory and advisory diagnostics.
  struct Report: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "report",
      abstract: "EXPERIMENTAL: Report OKF bundle inventory and advisory diagnostics",
      discussion: """
        Reports OKF bundle counts, type distribution, recommended-field coverage, and citations.
        Report mode is informational and does not fail because of validation or advisory issues.

        Example: md-utils okf report ./knowledge/ --format json
        """
    )

    @Argument(help: "Path to the OKF bundle directory; defaults to the current directory", completion: .directory, transform: { Path($0) })
    var bundlePath: Path = .current

    @Option(name: .long, help: "Output format: terminal or json")
    var format: OKFReportFormat = .terminal

    mutating func run() async throws {
      let analysis = try OKFAnalyzer.analyze(bundlePath: bundlePath)
      print(try OKFReportFormatter.render(analysis, format: format))
    }
  }
}
