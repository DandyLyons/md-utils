//
//  RulesCommandsTests.swift
//  md-utilsTests
//

import ArgumentParser
import Foundation
import PathKit
import Testing

@testable import md_utils

@Suite("rules commands", .serialized)
struct RulesCommandsTests {
  @Test
  func `rules command group has correct configuration`() {
    let config = CLIEntry.RulesCommands.configuration

    #expect(config.commandName == "rules")
    #expect(config.subcommands.count == 6)
    #expect(config.subcommands[0] is CLIEntry.RulesCommands.Init.Type)
    #expect(config.subcommands[1] is CLIEntry.RulesCommands.Add.Type)
    #expect(config.subcommands[2] is CLIEntry.RulesCommands.Remove.Type)
    #expect(config.subcommands[3] is CLIEntry.RulesCommands.List.Type)
    #expect(config.subcommands[4] is CLIEntry.RulesCommands.Describe.Type)
    #expect(config.subcommands[5] is CLIEntry.RulesCommands.Validate.Type)
  }

  @Test
  func `rules describe parses rule name`() throws {
    let parsed = try CLIEntry.parseAsRoot(["rules", "describe", "books"])
    let command = try #require(parsed as? CLIEntry.RulesCommands.Describe)

    #expect(command.schemaName == "books")
    #expect(command.format == .text)
  }

  @Test
  func `rules describe parses json format`() throws {
    let parsed = try CLIEntry.parseAsRoot(["rules", "describe", "books", "--format", "json"])
    let command = try #require(parsed as? CLIEntry.RulesCommands.Describe)

    #expect(command.schemaName == "books")
    #expect(command.format == .json)
  }

  @Test
  func `rules describe parses markdown format`() throws {
    let parsed = try CLIEntry.parseAsRoot(["rules", "describe", "books", "--format", "markdown"])
    let command = try #require(parsed as? CLIEntry.RulesCommands.Describe)

    #expect(command.schemaName == "books")
    #expect(command.format == .markdown)
  }

  @Test
  func `rules validate parses optional rule name`() throws {
    let parsed = try CLIEntry.parseAsRoot(["rules", "validate", "books"])
    let command = try #require(parsed as? CLIEntry.RulesCommands.Validate)

    #expect(command.ruleName == "books")
  }

  @Test
  func `rules validate parses include ok flag`() throws {
    let parsed = try CLIEntry.parseAsRoot(["rules", "validate", "--include-ok"])
    let command = try #require(parsed as? CLIEntry.RulesCommands.Validate)

    #expect(command.includeOk)
  }

  @Test
  func `rules validate output hides ok and skipped results by default`() throws {
    let summary = schemaValidationSummary()

    let output = RuleValidationSummaryFormatter.render(summary)

    #expect(output.contains("Rules validated: books."))
    #expect(output.contains("  ERROR Books/broken.md"))
    #expect(!output.contains("  OK Books/dune.md"))
    #expect(!output.contains("  SKIP Books/plain.md"))
  }

  @Test
  func `rules validate output shows rules when all files are ok`() throws {
    let summary = RuleValidationSummary(
      results: [
        RuleValidationResult(
          ruleName: "books",
          schemaPath: ".md-utils/schemas/book.schema.json",
          filePath: "Books/dune.md",
          status: .ok,
          errors: []
        ),
        RuleValidationResult(
          ruleName: "authors",
          schemaPath: ".md-utils/schemas/author.schema.json",
          filePath: "Authors/herbert.md",
          status: .ok,
          errors: []
        ),
      ],
      totalMarkdownFiles: 2
    )

    let output = RuleValidationSummaryFormatter.render(summary)

    #expect(output.contains("Rules validated: authors, books."))
    #expect(!output.contains("  OK Books/dune.md"))
    #expect(!output.contains("  OK Authors/herbert.md"))
  }

  @Test
  func `rules validate output includes ok results with include ok flag`() throws {
    let summary = schemaValidationSummary()

    let output = RuleValidationSummaryFormatter.render(summary, includeOk: true)

    #expect(output.contains("  ERROR Books/broken.md"))
    #expect(output.contains("  OK Books/dune.md"))
    #expect(output.contains("  SKIP Books/plain.md"))
  }

  @Test
  func `rules init creates config schema and rule`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot([
        "rules", "init", "books", "--path", "Books/**/*.md", "--tag", "Book",
      ])
      var command = try #require(parsed as? CLIEntry.RulesCommands.Init)
      try await command.run()

      #expect((project + ".md-utils/md-utils.json").exists)
      #expect((project + ".md-utils/md-utils.schema.json").exists)
      #expect((project + ".md-utils/schemas/books.schema.json").exists)

      let config = try MdUtilsConfig.load()
      #expect(config.configVersion == "0.2.0")
      #expect(config.schemaReference == "https://dandylyons.github.io/md-utils/schemas/0.2.0/md-utils.schema.json")
      #expect(config.schemaRules.count == 1)
      #expect(config.schemaRules.first?.name == "books")
      #expect(config.schemaRules.first?.match.paths == ["Books/**/*.md"])

      let configData = try Data(contentsOf: URL(fileURLWithPath: (project + ".md-utils/md-utils.json").string))
      let configObject = try #require(JSONSerialization.jsonObject(with: configData) as? [String: Any])
      #expect(configObject["configVersion"] as? String == "0.2.0")
      #expect(configObject["$schema"] as? String == "https://dandylyons.github.io/md-utils/schemas/0.2.0/md-utils.schema.json")
      #expect(configObject["rules"] != nil)
    }
  }

  @Test
  func `versioned config loads current schema version`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try withCurrentDirectory(project) {
      let config = try MdUtilsConfig.load()

      #expect(config.configVersion == "0.1.0")
      #expect(config.schemaRules.count == 1)
    }
  }

  @Test
  func `unversioned config loads as legacy current schema version`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project, includeConfigVersion: false)

    try withCurrentDirectory(project) {
      let config = try MdUtilsConfig.load()

      #expect(config.configVersion == "0.1.0")
      #expect(config.schemaRules.count == 1)
    }
  }

  @Test
  func `unsupported future config version fails before parsing rules`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project, configVersion: "99.0.0", rules: ["{ \"name\": \"broken\" }"])

    try withCurrentDirectory(project) {
      do {
        _ = try MdUtilsConfig.load()
        Issue.record("Expected unsupported configVersion to throw")
      } catch {
        #expect(String(describing: error).contains("Unsupported md-utils configVersion \"99.0.0\""))
      }
    }
  }

  @Test
  func `non string config version fails clearly`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    let mdUtils = project + ".md-utils"
    try mdUtils.mkpath()
    try (mdUtils + "md-utils.json").write("""
      {
        "configVersion": 1,
        "schemaDirectory": ".md-utils/schemas/",
        "schemaRules": []
      }
      """)

    try withCurrentDirectory(project) {
      do {
        _ = try MdUtilsConfig.load()
        Issue.record("Expected non-string configVersion to throw")
      } catch {
        #expect(String(describing: error).contains("configVersion must be a non-empty string"))
      }
    }
  }

  @Test
  func `current config is validated against bundled schema`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    let mdUtils = project + ".md-utils"
    try mdUtils.mkpath()
    try (mdUtils + "md-utils.json").write("""
      {
        "configVersion": "0.1.0",
        "schemaDirectory": ".md-utils/schemas/",
        "schemaRules": [],
        "unexpected": true
      }
      """)

    try withCurrentDirectory(project) {
      do {
        _ = try MdUtilsConfig.load()
        Issue.record("Expected config schema validation to throw")
      } catch {
        #expect(String(describing: error).contains("Project config is invalid for configVersion \"0.1.0\""))
      }
    }
  }

  @Test
  func `rules list runs with configured rules`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["rules", "list"])
      var command = try #require(parsed as? CLIEntry.RulesCommands.List)

      try await command.run()
    }
  }

  @Test
  func `rules describe loads configured rule and schema`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try withCurrentDirectory(project) {
      let description = try RuleDescriptionBuilder.describe(ruleName: "books")

      #expect(description.rule.name == "books")
      #expect(description.schemaPath?.string == ".md-utils/schemas/book.schema.json")
      #expect(description.jsonSchema["type"] as? String == "object")
    }
  }

  @Test
  func `rules describe fails for missing rule`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    let _: Void = try withCurrentDirectory(project) {
      #expect(throws: Error.self) {
        try RuleDescriptionBuilder.describe(ruleName: "missing")
      }
    }
  }

  @Test
  func `rules describe fails for missing schema file`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(
      project,
      rules: [ruleJSON(name: "books", schema: "missing.schema.json", paths: ["Books/**/*.md"])],
      schemas: [:]
    )

    let _: Void = try withCurrentDirectory(project) {
      #expect(throws: Error.self) {
        try RuleDescriptionBuilder.describe(ruleName: "books")
      }
    }
  }

  @Test
  func `rules describe human output summarizes rule and all fields`() throws {
    let description = RuleDescription(
      rule: Rule(
        name: "people-in-the-bible",
        schema: "people.schema.json",
        frontmatterRequired: true,
        match: RuleMatch(
          paths: ["People/**/*.md"],
          excludePaths: ["People/Drafts/**/*.md"],
          frontmatter: ["tags": FrontmatterMatcher(includes: "Person")]
        )
      ),
      schemaPath: ".md-utils/schemas/people.schema.json",
      jsonSchema: peopleSchemaObject()
    )

    let output = RuleDescriptionFormatter.render(description)

    #expect(output.contains("Rule Name:"))
    #expect(output.contains("people-in-the-bible"))
    #expect(output.contains("Rule"))
    #expect(output.contains("Applies to Markdown files matching People/**/*.md."))
    #expect(output.contains("Excludes People/Drafts/**/*.md."))
    #expect(output.contains("Runs only when tags includes \"Person\"."))
    #expect(output.contains("Schema Definition"))
    #expect(output.contains("name-meaning"))
    #expect(output.contains("Type:"))
    #expect(output.contains("String"))
    #expect(output.contains("REQUIRED"))
    #expect(output.contains("minLength 1"))
    #expect(output.contains("scripture-references[]"))
    #expect(output.contains("scripture-references[].book"))
    #expect(output.contains("scripture-references[].chapter"))
  }

  @Test
  func `rules describe json output includes rule and embedded schema`() throws {
    let description = RuleDescription(
      rule: Rule(
        name: "people-in-the-bible",
        schema: "people.schema.json",
        match: RuleMatch(paths: ["People/**/*.md"])
      ),
      schemaPath: ".md-utils/schemas/people.schema.json",
      jsonSchema: peopleSchemaObject()
    )

    let object = RuleDescriptionJSONRenderer.render(description)
    let rule = try #require(object["rule"] as? [String: Any])
    let match = try #require(rule["match"] as? [String: Any])
    let jsonSchema = try #require(object["jsonSchema"] as? [String: Any])
    let properties = try #require(jsonSchema["properties"] as? [String: Any])

    #expect(rule["name"] as? String == "people-in-the-bible")
    #expect(rule["schemaPath"] as? String == ".md-utils/schemas/people.schema.json")
    #expect(match["paths"] as? [String] == ["People/**/*.md"])
    #expect(properties["name-meaning"] != nil)
  }

  @Test
  func `rules describe markdown output renders sections and fields`() throws {
    let description = RuleDescription(
      rule: Rule(
        name: "people-in-the-bible",
        schema: "people.schema.json",
        frontmatterRequired: true,
        match: RuleMatch(paths: ["People/**/*.md"])
      ),
      schemaPath: ".md-utils/schemas/people.schema.json",
      jsonSchema: peopleSchemaObject()
    )

    let output = RuleDescriptionMarkdownFormatter.render(description)

    #expect(output.contains("# Rule Name: people-in-the-bible"))
    #expect(output.contains("## Rule"))
    #expect(output.contains("- Applies to Markdown files matching People/**/*.md."))
    #expect(output.contains("## Schema Definition"))
    #expect(output.contains("### name-meaning"))
    #expect(output.contains("- Type: String, REQUIRED, minLength 1"))
    #expect(output.contains("### scripture-references[].chapter"))
    #expect(!output.contains("\u{001B}"))
  }

  @Test
  func `rules add adds rule to existing config`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project, rules: [], schemas: [:])

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot([
        "rules", "add", "books", "--path", "Books/**/*.md", "--tag", "Book",
      ])
      var command = try #require(parsed as? CLIEntry.RulesCommands.Add)
      try await command.run()

      let config = try MdUtilsConfig.load()
      #expect(config.schemaRules.count == 1)
      #expect(config.schemaRules.first?.name == "books")
      #expect((project + ".md-utils/schemas/books.schema.json").exists)
    }
  }

  @Test
  func `rules add requires existing config`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["rules", "add", "books"])
      var command = try #require(parsed as? CLIEntry.RulesCommands.Add)

      await #expect(throws: Error.self) {
        try await command.run()
      }
    }
  }

  @Test
  func `rules add fails on duplicate rule`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["rules", "add", "books"])
      var command = try #require(parsed as? CLIEntry.RulesCommands.Add)

      await #expect(throws: Error.self) {
        try await command.run()
      }
    }
  }

  @Test
  func `rules remove removes rule and preserves schema by default`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["rules", "remove", "books"])
      var command = try #require(parsed as? CLIEntry.RulesCommands.Remove)
      try await command.run()

      let config = try MdUtilsConfig.load()
      #expect(config.schemaRules.isEmpty)
      #expect((project + ".md-utils/schemas/book.schema.json").exists)
    }
  }

  @Test
  func `rules remove fails for missing rule`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["rules", "remove", "missing"])
      var command = try #require(parsed as? CLIEntry.RulesCommands.Remove)

      await #expect(throws: Error.self) {
        try await command.run()
      }
    }
  }

  @Test
  func `rules remove delete schema deletes unshared schema file`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["rules", "remove", "books", "--delete-schema"])
      var command = try #require(parsed as? CLIEntry.RulesCommands.Remove)
      try await command.run()

      let config = try MdUtilsConfig.load()
      #expect(config.schemaRules.isEmpty)
      #expect(!(project + ".md-utils/schemas/book.schema.json").exists)
    }
  }

  @Test
  func `rules remove delete schema preserves shared schema file`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(
      project,
      rules: [
        ruleJSON(name: "books", schema: "book.schema.json", paths: ["Books/**/*.md"]),
        ruleJSON(name: "novels", schema: "book.schema.json", paths: ["Novels/**/*.md"]),
      ]
    )

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["rules", "remove", "books", "--delete-schema"])
      var command = try #require(parsed as? CLIEntry.RulesCommands.Remove)
      try await command.run()

      let config = try MdUtilsConfig.load()
      #expect(config.schemaRules.count == 1)
      #expect(config.schemaRules.first?.name == "novels")
      #expect((project + ".md-utils/schemas/book.schema.json").exists)
    }
  }

  @Test
  func `path and tags includes matching validates matching files only`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)
    try writeFile(project + "Books/dune.md", content: bookMarkdown(title: "Dune", tags: ["Book"]))
    try writeFile(project + "Books/note.md", content: bookMarkdown(title: "Note", tags: ["Note"]))
    try writeFile(project + "Other/book.md", content: bookMarkdown(title: "Other", tags: ["Book"]))

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate()

      #expect(summary.fileRuleMatches == 1)
      #expect(summary.results.first?.filePath == "Books/dune.md")
      #expect(summary.results.first?.status == .ok)
    }
  }

  @Test
  func `double star path rule matches files in descendant folders`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(
      project,
      rules: [ruleJSON(
        name: "integrations",
        schema: "integration.schema.json",
        paths: ["INTEGRATIONS/**/*.md"],
        frontmatter: "\"tags\": { \"includes\": \"Integration\" }"
      )],
      schemas: ["integration.schema.json": requiredStringSchema(required: "title")]
    )
    try writeFile(project + "INTEGRATIONS/top.md", content: bookMarkdown(title: "Top", tags: ["Integration"]))
    try writeFile(project + "INTEGRATIONS/Child/grandchild.md", content: bookMarkdown(title: "Grandchild", tags: ["Integration"]))
    try writeFile(project + "INTEGRATIONS/Child/Grandchild/deep.md", content: bookMarkdown(title: "Deep", tags: ["Integration"]))

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate(ruleName: "integrations")
      let files = Set(summary.results.map(\.filePath))

      #expect(files == [
        "INTEGRATIONS/top.md",
        "INTEGRATIONS/Child/grandchild.md",
        "INTEGRATIONS/Child/Grandchild/deep.md",
      ])
      #expect(!summary.hasFailures)
    }
  }

  @Test
  func `missing frontmatter does not match rule with frontmatter matcher`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(
      project,
      rules: [ruleJSON(
        name: "integrations",
        schema: "integration.schema.json",
        paths: ["INTEGRATIONS/**/*.md"],
        frontmatter: "\"tags\": { \"includes\": \"Integration\" }"
      )],
      schemas: ["integration.schema.json": requiredStringSchema(required: "title")]
    )
    try writeFile(project + "INTEGRATIONS/INTEGRATIONS_README.md", content: "# Integrations\n")
    try writeFile(project + "INTEGRATIONS/github.md", content: bookMarkdown(title: "GitHub", tags: ["Integration"]))

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate(ruleName: "integrations")

      #expect(summary.fileRuleMatches == 1)
      #expect(summary.results.first?.filePath == "INTEGRATIONS/github.md")
      #expect(!summary.hasFailures)
    }
  }

  @Test
  func `same file can be validated by multiple rules`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(
      project,
      rules: [
        ruleJSON(name: "books", schema: "book.schema.json", paths: ["Books/**/*.md"]),
        ruleJSON(name: "published", schema: "published.schema.json", paths: ["Books/**/*.md"]),
      ],
      schemas: [
        "book.schema.json": requiredStringSchema(required: "title"),
        "published.schema.json": requiredBooleanSchema(required: "published"),
      ]
    )
    try writeFile(
      project + "Books/dune.md",
      content: """
        ---
        title: Dune
        published: true
        ---
        # Dune
        """
    )

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate()

      #expect(summary.matchedFiles == 1)
      #expect(summary.fileRuleMatches == 2)
      #expect(!summary.hasFailures)
    }
  }

  @Test
  func `files matching no rules are ignored`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)
    try writeFile(project + "Notes/plain.md", content: "# Plain\n")

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate()

      #expect(summary.results.isEmpty)
      #expect(!summary.hasFailures)
    }
  }

  @Test
  func `missing frontmatter is an error when required`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(
      project,
      rules: [ruleJSON(name: "books", schema: "book.schema.json", paths: ["Books/**/*.md"])]
    )
    try writeFile(project + "Books/plain.md", content: "# Plain\n")

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate()

      #expect(summary.hasFailures)
      #expect(summary.results.first?.status == .error)
      #expect(summary.results.first?.errors.first?.message == "required by rule \"books\"")
    }
  }

  @Test
  func `missing frontmatter is skipped when not required`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(
      project,
      rules: [ruleJSON(
        name: "books",
        schema: "book.schema.json",
        paths: ["Books/**/*.md"],
        frontmatterRequired: false
      )]
    )
    try writeFile(project + "Books/plain.md", content: "# Plain\n")

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate()

      #expect(!summary.hasFailures)
      #expect(summary.results.first?.status == .skipped)
      #expect(summary.results.first?.errors.first?.message == "not present")
    }
  }

  @Test
  func `invalid YAML frontmatter fails validation`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)
    try writeFile(
      project + "Books/broken.md",
      content: """
        ---
        title: [
        ---
        # Broken
        """
    )

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate()

      #expect(summary.hasFailures)
      #expect(summary.results.first?.errors.first?.path == "frontmatter")
      #expect(summary.results.first?.errors.first?.message.contains("invalid YAML") == true)
    }
  }

  @Test
  func `schema errors report JSON pointer path`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)
    try writeFile(project + "Books/dune.md", content: bookMarkdown(tags: ["Book"]))

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate()

      #expect(summary.hasFailures)
      #expect(summary.results.first?.status == .error)
      #expect(summary.results.first?.errors.isEmpty == false)
    }
  }

  @Test
  func `YAML to JSON edge cases validate documented types`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(
      project,
      rules: [ruleJSON(name: "types", schema: "types.schema.json", paths: ["Types/**/*.md"])],
      schemas: [
        "types.schema.json": """
          {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "type": "object",
            "required": ["stringValue", "integerValue", "floatValue", "booleanValue", "nullValue", "arrayValue", "objectValue", "dateValue"],
            "properties": {
              "stringValue": { "type": "string" },
              "integerValue": { "type": "integer" },
              "floatValue": { "type": "number" },
              "booleanValue": { "type": "boolean" },
              "nullValue": { "type": "null" },
              "arrayValue": { "type": "array", "items": { "type": "string" } },
              "objectValue": { "type": "object", "properties": { "nested": { "type": "string" } } },
              "dateValue": { "type": "string" }
            }
          }
          """,
      ]
    )
    try writeFile(
      project + "Types/all.md",
      content: """
        ---
        stringValue: hello
        integerValue: 42
        floatValue: 3.14
        booleanValue: true
        nullValue: null
        arrayValue:
          - one
          - two
        objectValue:
          nested: value
        dateValue: 2026-05-20
        ---
        # Types
        """
    )

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate()

      #expect(!summary.hasFailures)
      #expect(summary.results.first?.status == .ok)
    }
  }

  @Test
  func `empty frontmatter validates as empty object`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(
      project,
      rules: [ruleJSON(name: "empty", schema: "empty.schema.json", paths: ["Empty/**/*.md"])],
      schemas: ["empty.schema.json": "{ \"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"type\": \"object\", \"maxProperties\": 0 }"]
    )
    try writeFile(
      project + "Empty/empty.md",
      content: """
        ---
        ---
        # Empty
        """
    )

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate()

      #expect(!summary.hasFailures)
      #expect(summary.results.first?.status == .ok)
    }
  }

  @Test
  func `v2 boolean equals matcher selects matching files`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeRulesProject(project, rules: [ruleV2JSON(
      name: "published",
      paths: ["Posts/**/*.md"],
      frontmatter: "\"publish\": { \"equals\": true }",
      checks: ["{ \"type\": \"maxBodyLines\", \"max\": 10 }"]
    )])
    try writeFile(project + "Posts/live.md", content: "---\npublish: true\n---\n# Live\n")
    try writeFile(project + "Posts/draft.md", content: "---\npublish: false\n---\n# Draft\n")

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate(ruleName: "published")

      #expect(summary.fileRuleMatches == 1)
      #expect(summary.results.first?.filePath == "Posts/live.md")
      #expect(!summary.hasFailures)
    }
  }

  @Test
  func `v2 not includes matcher excludes arrays containing value`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeRulesProject(project, rules: [ruleV2JSON(
      name: "current",
      paths: ["Notes/**/*.md"],
      frontmatter: "\"tags\": { \"notIncludes\": \"DEPRECATED\" }",
      checks: ["{ \"type\": \"maxBodyLines\", \"max\": 10 }"]
    )])
    try writeFile(project + "Notes/current.md", content: "---\ntags: [Current]\n---\n# Current\n")
    try writeFile(project + "Notes/old.md", content: "---\ntags: [DEPRECATED]\n---\n# Old\n")

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate(ruleName: "current")

      #expect(summary.fileRuleMatches == 1)
      #expect(summary.results.first?.filePath == "Notes/current.md")
    }
  }

  @Test
  func `v2 after and between date matchers select dates`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeRulesProject(project, rules: [
      ruleV2JSON(
        name: "after-2000",
        paths: ["Dates/**/*.md"],
        frontmatter: "\"date\": { \"after\": \"2000-01-01\" }",
        checks: ["{ \"type\": \"maxBodyLines\", \"max\": 10 }"]
      ),
      ruleV2JSON(
        name: "range",
        paths: ["Dates/**/*.md"],
        frontmatter: "\"date\": { \"between\": { \"from\": \"2000-01-01\", \"to\": \"2015-04-01\" } }",
        checks: ["{ \"type\": \"maxBodyWords\", \"max\": 10 }"]
      ),
    ])
    try writeFile(project + "Dates/old.md", content: "---\ndate: 1999-12-31\n---\n# Old\n")
    try writeFile(project + "Dates/mid.md", content: "---\ndate: 2010-06-01\n---\n# Mid\n")
    try writeFile(project + "Dates/new.md", content: "---\ndate: 2020-01-01\n---\n# New\n")

    try withCurrentDirectory(project) {
      let after = try RulesValidatorRunner.validate(ruleName: "after-2000")
      let range = try RulesValidatorRunner.validate(ruleName: "range")

      #expect(Set(after.results.map(\.filePath)) == ["Dates/mid.md", "Dates/new.md"])
      #expect(Set(range.results.map(\.filePath)) == ["Dates/mid.md"])
    }
  }

  @Test
  func `v2 missing frontmatter key does not match predicate`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeRulesProject(project, rules: [ruleV2JSON(
      name: "published",
      paths: ["Posts/**/*.md"],
      frontmatter: "\"publish\": { \"equals\": true }",
      checks: ["{ \"type\": \"maxBodyLines\", \"max\": 10 }"]
    )])
    try writeFile(project + "Posts/missing.md", content: "---\ntitle: Missing\n---\n# Missing\n")

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate(ruleName: "published")

      #expect(summary.results.isEmpty)
    }
  }

  @Test
  func `v2 document checks report required heading and body limits`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeRulesProject(project, rules: [ruleV2JSON(
      name: "body",
      paths: ["Docs/**/*.md"],
      checks: [
        "{ \"type\": \"requiredHeading\", \"heading\": \"Footnotes\" }",
        "{ \"type\": \"maxBodyLines\", \"max\": 2 }",
        "{ \"type\": \"maxBodyWords\", \"max\": 4 }",
      ]
    )])
    try writeFile(project + "Docs/bad.md", content: "# Title\n\nOne two three four five\n")

    try withCurrentDirectory(project) {
      let summary = try RulesValidatorRunner.validate(ruleName: "body")
      let paths = Set(summary.results.flatMap { $0.errors.map(\.path) })

      #expect(summary.hasFailures)
      #expect(paths == ["heading", "body.lines", "body.words"])
    }
  }

  private func createTempProject() throws -> Path {
    let path = Path(NSTemporaryDirectory()) + "md-utils-schema-tests-\(UUID().uuidString)"
    try path.mkpath()
    return path
  }

  private func withCurrentDirectory<T>(_ path: Path, operation: () async throws -> T) async throws -> T {
    let original = FileManager.default.currentDirectoryPath
    guard FileManager.default.changeCurrentDirectoryPath(path.string) else {
      throw ValidationError("Failed to change current directory to \(path.string)")
    }
    defer { _ = FileManager.default.changeCurrentDirectoryPath(original) }
    return try await operation()
  }

  private func withCurrentDirectory<T>(_ path: Path, operation: () throws -> T) throws -> T {
    let original = FileManager.default.currentDirectoryPath
    guard FileManager.default.changeCurrentDirectoryPath(path.string) else {
      throw ValidationError("Failed to change current directory to \(path.string)")
    }
    defer { _ = FileManager.default.changeCurrentDirectoryPath(original) }
    return try operation()
  }

  private func writeSchemaProject(
    _ project: Path,
    configVersion: String = "0.1.0",
    includeConfigVersion: Bool = true,
    rules: [String]? = nil,
    schemas: [String: String]? = nil
  ) throws {
    let mdUtils = project + ".md-utils"
    let schemaDir = mdUtils + "schemas"
    try schemaDir.mkpath()

    let ruleEntries = rules ?? [ruleJSON(
      name: "books",
      schema: "book.schema.json",
      paths: ["Books/**/*.md"],
      frontmatter: "\"tags\": { \"includes\": \"Book\" }"
    )]
    let configVersionLine = includeConfigVersion ? "\n  \"configVersion\": \"\(configVersion)\"," : ""
    try (mdUtils + "md-utils.json").write("""
      {
        "$schema": "https://dandylyons.github.io/md-utils/schemas/0.1.0/md-utils.schema.json",
      \(configVersionLine)
        "schemaDirectory": ".md-utils/schemas/",
        "schemaRules": [
          \(ruleEntries.joined(separator: ",\n"))
        ]
      }
      """)

    let schemaEntries = schemas ?? ["book.schema.json": requiredStringSchema(required: "title")]
    for (filename, content) in schemaEntries {
      try (schemaDir + filename).write(content)
    }
  }

  private func writeRulesProject(
    _ project: Path,
    rules: [String],
    schemas: [String: String] = [:]
  ) throws {
    let mdUtils = project + ".md-utils"
    let schemaDir = mdUtils + "schemas"
    try schemaDir.mkpath()

    try (mdUtils + "md-utils.json").write("""
      {
        "$schema": "https://dandylyons.github.io/md-utils/schemas/0.2.0/md-utils.schema.json",
        "configVersion": "0.2.0",
        "schemaDirectory": ".md-utils/schemas/",
        "rules": [
          \(rules.joined(separator: ",\n"))
        ]
      }
      """)

    for (filename, content) in schemas {
      try (schemaDir + filename).write(content)
    }
  }

  private func writeFile(_ path: Path, content: String) throws {
    try path.parent().mkpath()
    try path.write(content)
  }

  private func schemaValidationSummary() -> RuleValidationSummary {
    RuleValidationSummary(
      results: [
        RuleValidationResult(
          ruleName: "books",
          schemaPath: ".md-utils/schemas/book.schema.json",
          filePath: "Books/dune.md",
          status: .ok,
          errors: []
        ),
        RuleValidationResult(
          ruleName: "books",
          schemaPath: ".md-utils/schemas/book.schema.json",
          filePath: "Books/plain.md",
          status: .skipped,
          errors: [RuleValidationErrorDetail(path: "frontmatter", message: "not present")]
        ),
        RuleValidationResult(
          ruleName: "books",
          schemaPath: ".md-utils/schemas/book.schema.json",
          filePath: "Books/broken.md",
          status: .error,
          errors: [RuleValidationErrorDetail(path: "/title", message: "is required")]
        ),
      ],
      totalMarkdownFiles: 3
    )
  }

  private func ruleJSON(
    name: String,
    schema: String,
    paths: [String],
    frontmatterRequired: Bool = true,
    frontmatter: String? = nil
  ) -> String {
    let quotedPaths = paths.map { "\"\($0)\"" }.joined(separator: ", ")
    let frontmatterBlock = frontmatter.map { ",\n        \"frontmatter\": { \($0) }" } ?? ""
    return """
      {
        "name": "\(name)",
        "schema": "\(schema)",
        "frontmatterRequired": \(frontmatterRequired),
        "match": {
          "paths": [\(quotedPaths)]\(frontmatterBlock)
        }
      }
      """
  }

  private func ruleV2JSON(
    name: String,
    paths: [String],
    frontmatter: String? = nil,
    checks: [String]
  ) -> String {
    let quotedPaths = paths.map { "\"\($0)\"" }.joined(separator: ", ")
    let frontmatterBlock = frontmatter.map { ",\n        \"frontmatter\": { \($0) }" } ?? ""
    return """
      {
        "name": "\(name)",
        "match": {
          "paths": [\(quotedPaths)]\(frontmatterBlock)
        },
        "checks": [
          \(checks.joined(separator: ",\n"))
        ]
      }
      """
  }

  private func requiredStringSchema(required: String) -> String {
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["\(required)"],
      "properties": {
        "\(required)": { "type": "string" }
      }
    }
    """
  }

  private func requiredBooleanSchema(required: String) -> String {
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["\(required)"],
      "properties": {
        "\(required)": { "type": "boolean" }
      }
    }
    """
  }

  private func peopleSchemaObject() -> [String: Any] {
    [
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["name-meaning"],
      "properties": [
        "name-meaning": [
          "type": "string",
          "minLength": 1,
        ],
        "scripture-references": [
          "type": "array",
          "minItems": 1,
          "items": [
            "type": "object",
            "required": ["book", "chapter"],
            "properties": [
              "book": ["type": "string"],
              "chapter": ["type": "integer", "minimum": 1],
            ],
          ],
        ],
      ],
    ]
  }

  private func bookMarkdown(title: String? = nil, tags: [String]) -> String {
    let titleLine = title.map { "title: \($0)\n" } ?? ""
    let tagLines = tags.map { "  - \($0)" }.joined(separator: "\n")
    return """
      ---
      \(titleLine)tags:
      \(tagLines)
      ---
      # Book
      """
  }
}
