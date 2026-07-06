//
//  RulesList.swift
//  md-utils
//

import ArgumentParser
/// Adds Markdown document behavior to ``CLIEntry.RulesCommands``.
///
/// See <doc:RulesValidationCommands> for workflow details.
extension CLIEntry.RulesCommands {
  /// Defines the `rules list` command behavior.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "list",
      abstract: "List configured rules"
    )
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:RulesValidationCommands> for workflow details.
    mutating func run() async throws {
      let config = try MdUtilsConfig.load()
      if config.schemaRules.isEmpty {
        print(CLIStyle.muted("No rules configured."))
        return
      }

      for rule in config.schemaRules {
        print(CLIStyle.heading(rule.name))
        if !rule.schema.isEmpty {
          let schemaPath = RulesPaths.schemaFile(rule: rule, config: config)
          print("  \(CLIStyle.metadata("schema:")) \(CLIStyle.path(schemaPath.string))")
        }
        print("  \(CLIStyle.metadata("frontmatterRequired:")) \(rule.frontmatterRequired)")
        print("  \(CLIStyle.metadata("checks:")) \(rule.checks.map(describeCheck).joined(separator: ", "))")
        if !rule.match.paths.isEmpty {
          print("  \(CLIStyle.metadata("paths:")) \(rule.match.paths.joined(separator: ", "))")
        }
        if !rule.match.frontmatter.isEmpty {
          print("  \(CLIStyle.metadata("\(rule.name) rule will run when:"))")
          for key in rule.match.frontmatter.keys.sorted() {
            if let matcher = rule.match.frontmatter[key] {
              for operatorName in matcher.operators.keys.sorted() {
                if let value = matcher.operators[operatorName] {
                  print("    \(CLIStyle.metadata("frontmatter key")) \(key) \(CLIStyle.metadata(operatorName)) \(value)")
                }
              }
            }
          }
        }
      }
    }

    private func describeCheck(_ check: RuleCheck) -> String {
      switch check {
      case .frontmatterSchema(let schema, _):
        return "frontmatterSchema(\(schema))"
      case .requiredHeading(let heading):
        return "requiredHeading(\(heading))"
      case .maxBodyLines(let max):
        return "maxBodyLines(\(max))"
      case .maxBodyWords(let max):
        return "maxBodyWords(\(max))"
      }
    }
  }
}
