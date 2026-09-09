//
//  RulesAdd.swift
//  md-utils
//

import ArgumentParser
/// Adds Markdown document behavior to ``CLIEntry.RulesCommands``.
///
/// See <doc:RulesValidationCommands> for workflow details.
extension CLIEntry.RulesCommands {
  /// Defines the `rules add` command behavior.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "add",
      abstract: "Add a rule to existing project configuration"
    )

    @Argument(help: "Rule name to create")
    var name: String

    @Option(name: .long, help: "Schema filename to create inside schemaDirectory")
    var schema: String?

    @Option(name: .long, help: "Existing .mdtype filename relative to types/ (config 0.3.0)")
    var type: String?
    @OptionGroup var project: RuleProjectOptions

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
      if let type {
        guard schema == nil && frontmatterRequired else {
          throw ValidationError("With --type, configure schema and frontmatter presence in the type definition")
        }
        let file = try RuleManager.addStandaloneRule(name: name, type: type, path: path, tag: tag,
          configPath: project.configPath, projectRoot: project.root)
        print("Created rule \"\(name)\": \(file.string)")
        return
      }
      let schemaFile = try RuleManager.addRule(RuleOptions(
        name: name,
        schema: schema,
        path: path,
        tag: tag,
        frontmatterRequired: frontmatterRequired,
      ), configPath: project.configPath, projectRoot: project.root)

      print("\(CLIStyle.success("Created rule")) \"\(name)\"")
      print("\(CLIStyle.metadata("Config:")) \(CLIStyle.path(RulesPaths.configFile.string))")
      print("\(CLIStyle.metadata("Schema:")) \(CLIStyle.path(schemaFile.string))")
    }
  }
}
