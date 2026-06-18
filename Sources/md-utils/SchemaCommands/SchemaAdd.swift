//
//  SchemaAdd.swift
//  md-utils
//

import ArgumentParser
/// Adds Markdown document behavior to ``CLIEntry.SchemaCommands``.
///
/// See <doc:SchemaValidationCommands> for workflow details.
extension CLIEntry.SchemaCommands {
  /// Defines the `SchemaAdd` command behavior.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "add",
      abstract: "Add a schema rule to existing project configuration"
    )

    @Argument(help: "Rule name to create")
    var name: String

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
      let schemaFile = try SchemaRuleManager.addRule(SchemaRuleOptions(
        name: name,
        schema: schema,
        path: path,
        tag: tag,
        frontmatterRequired: frontmatterRequired,
      ))

      print("\(CLIStyle.success("Created schema rule")) \"\(name)\"")
      print("\(CLIStyle.metadata("Config:")) \(CLIStyle.path(SchemaPaths.configFile.string))")
      print("\(CLIStyle.metadata("Schema:")) \(CLIStyle.path(schemaFile.string))")
    }
  }
}
