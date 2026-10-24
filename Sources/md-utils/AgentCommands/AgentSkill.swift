//
//  AgentSkill.swift
//  md-utils
//

import ArgumentParser
import Foundation
/// Adds Markdown document behavior to ``CLIEntry.AgentCommands``.
extension CLIEntry.AgentCommands {
  /// Defines the `AgentSkill` command behavior.
  struct AgentSkill: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "skill",
      abstract: "Print the skill entrypoint or export the complete skill folder",
      discussion: """
        Without options, prints SKILL.md only. Use --output-directory to export
        SKILL.md and all references for installation. The destination must not
        exist and its parent must exist. Existing installations are never replaced.
        If copying fails, inspect any partial destination and retry at a new path.
        """,
    )

    @Option(name: .long, help: "Export the complete skill to a new directory", completion: .directory)
    var outputDirectory: String?
    /// Runs the command using the parsed command-line arguments.
    mutating func run() async throws {
      let source = try Self.resourceDirectory()
      if let outputDirectory {
        let destination = URL(filePath: outputDirectory, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: source, to: destination)
        print("Exported complete skill to \(destination.path)")
        return
      }
      let url = source.appending(path: "SKILL.md")
      let content = try String(contentsOf: url, encoding: .utf8)
      print(content, terminator: "")
    }

    /// Locates the complete folder preserved by SwiftPM resource copying.
    static func resourceDirectory() throws -> URL {
      guard let url = Bundle.module.url(forResource: "AgentSkill", withExtension: nil) else {
        throw ValidationError("AgentSkill directory not found in bundle.")
      }
      return url
    }
  }
}
