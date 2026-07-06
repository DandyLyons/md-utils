//
//  RulesInit.swift
//  md-utils
//

import ArgumentParser
import Foundation
import PathKit
/// Adds Markdown document behavior to ``CLIEntry.RulesCommands``.
///
/// See <doc:RulesValidationCommands> for workflow details.
extension CLIEntry.RulesCommands {
  /// Defines the `rules init` command behavior.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "init",
      abstract: "Create project rules configuration and a frontmatter schema check"
    )

    @Argument(help: "Rule name to create")
    var name: String = "default"

    @Option(name: .long, help: "Schema filename to create inside schemaDirectory")
    var schema: String?

    @Option(name: .long, help: "Glob pattern for files matched by this rule")
    var path: String = "**/*.md"

    @Option(name: .long, help: "Require frontmatter key tags to include this value")
    var tag: String?

    @Flag(
      name: .customLong("frontmatter-required"),
      inversion: .prefixedNo,
      help: "Require matching files to have frontmatter"
    )
    var frontmatterRequired: Bool = true
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:RulesValidationCommands> for workflow details.
    mutating func run() async throws {
      try RulesConfigBootstrapper.ensureProjectFiles()

      let schemaFile = try RuleManager.addRule(RuleOptions(
        name: name,
        schema: schema,
        path: path,
        tag: tag,
        frontmatterRequired: frontmatterRequired,
      ))

      print("\(CLIStyle.success("Created rule")) \"\(name)\"")
      print("\(CLIStyle.metadata("Config:")) \(CLIStyle.path(RulesPaths.configFile.string))")
      print("\(CLIStyle.metadata("Schema:")) \(CLIStyle.path(schemaFile.string))")
    }
  }
}
