//
//  OKFValidate.swift
//  md-utils
//

import ArgumentParser
import PathKit

extension CLIEntry.OKFCommands {
  /// Validates an OKF v0.1 draft bundle.
  struct Validate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "validate",
      abstract: "EXPERIMENTAL: Validate an OKF v0.1 draft bundle",
      discussion: """
        EXPERIMENTAL: OKF validation behavior is likely to change as the OKF spec changes.

        Validates hard conformance rules from the OKF v0.1 draft.
        Directory paths in examples use trailing slashes, for example: md-utils okf validate ./knowledge/
        Spec: https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md
        """
    )

    @Argument(help: "Path to the OKF bundle directory", completion: .directory, transform: { Path($0) })
    var bundlePath: Path

    mutating func run() async throws {
      let timer = CommandTimer()
      let summary = try OKFValidator.validate(bundlePath: bundlePath)
      print(OKFValidationFormatter.render(summary))
      timer.writeStatus("Validated \(summary.conceptDocuments) OKF concept document(s)")
      if summary.hasErrors {
        throw ExitCode.failure
      }
    }
  }
}
