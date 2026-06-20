//
//  OKFCommands.swift
//  md-utils
//

import ArgumentParser

/// Adds OKF command implementations to ``CLIEntry``.
extension CLIEntry {
  /// Commands for Open Knowledge Format v0.1 draft bundles.
  struct OKFCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "okf",
      abstract: "EXPERIMENTAL: Work with OKF v0.1 draft Markdown knowledge bundles",
      discussion: """
        EXPERIMENTAL: OKF command behavior is likely to change as the OKF spec changes.

        OKF support targets the Open Knowledge Format v0.1 draft.
        Spec: https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md
        """,
      subcommands: [
        Validate.self,
        TypeCommands.self,
      ]
    )
  }
}
