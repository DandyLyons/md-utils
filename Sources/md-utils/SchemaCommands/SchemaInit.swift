//
//  Init.swift
//  md-utils
//

import ArgumentParser
import Foundation
import PathKit
/// Adds Markdown document behavior to ``CLIEntry.SchemaCommands``.
///
/// See <doc:SchemaValidationCommands> for workflow details.
extension CLIEntry.SchemaCommands {
  /// Defines the `SchemaInit` command behavior.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "init",
      abstract: "Create project schema configuration and a schema rule"
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
    /// See <doc:SchemaValidationCommands> for workflow details.
    mutating func run() async throws {
      try SchemaConfigBootstrapper.ensureProjectFiles()

      let schemaFile = try SchemaRuleManager.addRule(SchemaRuleOptions(
        name: name,
        schema: schema,
        path: path,
        tag: tag,
        frontmatterRequired: frontmatterRequired,
      ))

      print("Created schema rule \"\(name)\"")
      print("Config: \(SchemaPaths.configFile.string)")
      print("Schema: \(schemaFile.string)")
    }
  }
}
