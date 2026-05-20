//
//  Init.swift
//  md-utils
//

import ArgumentParser
import Foundation
import PathKit

extension CLIEntry.SchemaCommands {
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

    mutating func run() async throws {
      try SchemaConfigBootstrapper.ensureProjectFiles()

      var config = try MdUtilsConfig.load()
      if config.schemaRules.contains(where: { $0.name == name }) {
        throw ValidationError("Schema rule already exists: \"\(name)\"")
      }

      let schemaFilename = schema ?? "\(name).schema.json"
      let schemaDirectory = SchemaPaths.schemaDirectory(for: config)
      try schemaDirectory.mkpath()
      let schemaFile = schemaDirectory + schemaFilename
      if !schemaFile.exists {
        try schemaFile.write(starterSchema(title: name))
      }

      var frontmatterMatchers: [String: FrontmatterMatcher] = [:]
      if let tag {
        frontmatterMatchers["tags"] = FrontmatterMatcher(includes: tag)
      }

      let rule = SchemaRule(
        name: name,
        schema: schemaFilename,
        frontmatterRequired: frontmatterRequired,
        match: SchemaRuleMatch(paths: [path], frontmatter: frontmatterMatchers)
      )
      config.schemaRules.append(rule)
      try config.save()

      print("Created schema rule \"\(name)\"")
      print("Config: \(SchemaPaths.configFile.string)")
      print("Schema: \(schemaFile.string)")
    }

    private func starterSchema(title: String) -> String {
      """
      {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "\(title)",
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "title": {
            "type": "string"
          },
          "tags": {
            "type": "array",
            "items": {
              "type": "string"
            }
          }
        }
      }

      """
    }
  }
}
