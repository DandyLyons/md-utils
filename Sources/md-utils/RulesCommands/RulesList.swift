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

    @Flag(name: .long, help: "Show rule details")
    var verbose = false

    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:RulesValidationCommands> for workflow details.
    mutating func run() async throws {
      let config = try MdUtilsConfig.load()
      print(RulesListFormatter.render(config, verbose: verbose))
    }
  }
}

enum RulesListFormatter {
  static func render(_ config: MdUtilsConfig, verbose: Bool = false) -> String {
    if config.schemaRules.isEmpty {
      return CLIStyle.muted("No rules configured.")
    }

    if !verbose {
      var lines = config.schemaRules.map { CLIStyle.heading($0.name) }
      lines.append(CLIStyle.muted("Hint: Use --verbose to show rule details."))
      return lines.joined(separator: "\n")
    }

    var lines: [String] = []
    for rule in config.schemaRules {
      lines.append(CLIStyle.heading(rule.name))
      if !rule.schema.isEmpty {
        let schemaPath = RulesPaths.schemaFile(rule: rule, config: config)
        lines.append("  \(CLIStyle.metadata("schema:")) \(CLIStyle.path(schemaPath.string))")
      }
      lines.append("  \(CLIStyle.metadata("frontmatterRequired:")) \(rule.frontmatterRequired)")
      lines.append("  \(CLIStyle.metadata("checks:")) \(rule.checks.map(describeCheck).joined(separator: ", "))")
      if !rule.match.paths.isEmpty {
        lines.append("  \(CLIStyle.metadata("paths:")) \(rule.match.paths.joined(separator: ", "))")
      }
      if !rule.match.frontmatter.isEmpty {
        lines.append("  \(CLIStyle.metadata("\(rule.name) rule will run when:"))")
        for key in rule.match.frontmatter.keys.sorted() {
          if let matcher = rule.match.frontmatter[key] {
            for operatorName in matcher.operators.keys.sorted() {
              if let value = matcher.operators[operatorName] {
                lines.append("    \(CLIStyle.metadata("frontmatter key")) \(key) \(CLIStyle.metadata(operatorName)) \(value)")
              }
            }
          }
        }
      }
    }
    return lines.joined(separator: "\n")
  }

  private static func describeCheck(_ check: RuleCheck) -> String {
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
