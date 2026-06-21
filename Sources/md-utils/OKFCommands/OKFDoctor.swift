//
//  OKFDoctor.swift
//  md-utils
//

import ArgumentParser
import PathKit

extension CLIEntry.OKFCommands {
  /// Runs OKF conformance checks and advisory health diagnostics.
  struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "doctor",
      abstract: "EXPERIMENTAL: Diagnose OKF conformance and bundle health",
      discussion: """
        Runs hard OKF v0.1 draft conformance checks plus advisory diagnostics for agent usefulness.
        The command exits non-zero only when hard conformance errors are present.

        Example: md-utils okf doctor ./knowledge/
        """
    )

    @Argument(help: "Path to the OKF bundle directory; defaults to the current directory", completion: .directory, transform: { Path($0) })
    var bundlePath: Path = .current

    @Option(name: .long, help: "Output format: terminal or json")
    var format: OKFReportFormat = .terminal

    mutating func run() async throws {
      let timer = CommandTimer()
      let analysis = try OKFAnalyzer.analyze(bundlePath: bundlePath)
      print(try OKFReportFormatter.render(analysis, format: format))
      timer.writeStatus("Checked \(analysis.validation.conceptDocuments) OKF concept document(s)")
      if analysis.validation.hasErrors {
        throw ExitCode.failure
      }
    }
  }
}
