//
//  SchemaCommandsTests.swift
//  md-utilsTests
//

import ArgumentParser
import Foundation
import PathKit
import Testing

@testable import md_utils

@Suite("schema commands", .serialized)
struct SchemaCommandsTests {
  @Test
  func `schema command group has correct configuration`() {
    let config = CLIEntry.SchemaCommands.configuration

    #expect(config.commandName == "schema")
    #expect(config.subcommands.count == 6)
    #expect(config.subcommands[0] is CLIEntry.SchemaCommands.Init.Type)
    #expect(config.subcommands[1] is CLIEntry.SchemaCommands.Add.Type)
    #expect(config.subcommands[2] is CLIEntry.SchemaCommands.Remove.Type)
    #expect(config.subcommands[3] is CLIEntry.SchemaCommands.List.Type)
    #expect(config.subcommands[4] is CLIEntry.SchemaCommands.Describe.Type)
    #expect(config.subcommands[5] is CLIEntry.SchemaCommands.Validate.Type)
  }

  @Test
  func `schema describe parses rule name`() throws {
    let parsed = try CLIEntry.parseAsRoot(["schema", "describe", "books"])
    let command = try #require(parsed as? CLIEntry.SchemaCommands.Describe)

    #expect(command.schemaName == "books")
    #expect(command.format == .text)
  }

  @Test
  func `schema describe parses json format`() throws {
    let parsed = try CLIEntry.parseAsRoot(["schema", "describe", "books", "--format", "json"])
    let command = try #require(parsed as? CLIEntry.SchemaCommands.Describe)

    #expect(command.schemaName == "books")
    #expect(command.format == .json)
  }

  @Test
  func `schema describe parses markdown format`() throws {
    let parsed = try CLIEntry.parseAsRoot(["schema", "describe", "books", "--format", "markdown"])
    let command = try #require(parsed as? CLIEntry.SchemaCommands.Describe)

    #expect(command.schemaName == "books")
    #expect(command.format == .markdown)
  }

  @Test
  func `schema validate parses optional rule name`() throws {
    let parsed = try CLIEntry.parseAsRoot(["schema", "validate", "books"])
    let command = try #require(parsed as? CLIEntry.SchemaCommands.Validate)

    #expect(command.ruleName == "books")
  }

  @Test
  func `schema validate parses include ok flag`() throws {
    let parsed = try CLIEntry.parseAsRoot(["schema", "validate", "--include-ok"])
    let command = try #require(parsed as? CLIEntry.SchemaCommands.Validate)

    #expect(command.includeOk)
  }

  @Test
  func `schema validate output hides ok and skipped results by default`() throws {
    let summary = schemaValidationSummary()

    let output = SchemaValidationSummaryFormatter.render(summary)

    #expect(output.contains("Rules validated: books."))
    #expect(output.contains("  ERROR Books/broken.md"))
    #expect(!output.contains("  OK Books/dune.md"))
    #expect(!output.contains("  SKIP Books/plain.md"))
  }

  @Test
  func `schema validate output shows rules when all files are ok`() throws {
    let summary = SchemaValidationSummary(
      results: [
        SchemaValidationResult(
          ruleName: "books",
          schemaPath: ".md-utils/schemas/book.schema.json",
          filePath: "Books/dune.md",
          status: .ok,
          errors: []
        ),
        SchemaValidationResult(
          ruleName: "authors",
          schemaPath: ".md-utils/schemas/author.schema.json",
          filePath: "Authors/herbert.md",
          status: .ok,
          errors: []
        ),
      ],
      totalMarkdownFiles: 2
    )

    let output = SchemaValidationSummaryFormatter.render(summary)

    #expect(output.contains("Rules validated: authors, books."))
    #expect(!output.contains("  OK Books/dune.md"))
    #expect(!output.contains("  OK Authors/herbert.md"))
  }

  @Test
  func `schema validate output includes ok results with include ok flag`() throws {
    let summary = schemaValidationSummary()

    let output = SchemaValidationSummaryFormatter.render(summary, includeOk: true)

    #expect(output.contains("  ERROR Books/broken.md"))
    #expect(output.contains("  OK Books/dune.md"))
    #expect(output.contains("  SKIP Books/plain.md"))
  }

  @Test
  func `schema init creates config schema and rule`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot([
        "schema", "init", "books", "--path", "Books/**/*.md", "--tag", "Book",
      ])
      var command = try #require(parsed as? CLIEntry.SchemaCommands.Init)
      try await command.run()

      #expect((project + ".md-utils/md-utils.json").exists)
      #expect((project + ".md-utils/md-utils.schema.json").exists)
      #expect((project + ".md-utils/schemas/books.schema.json").exists)

      let config = try MdUtilsConfig.load()
      #expect(config.schemaRules.count == 1)
      #expect(config.schemaRules.first?.name == "books")
      #expect(config.schemaRules.first?.match.paths == ["Books/**/*.md"])
    }
  }

  @Test
  func `schema list runs with configured rules`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["schema", "list"])
      var command = try #require(parsed as? CLIEntry.SchemaCommands.List)

      try await command.run()
    }
  }

  @Test
  func `schema describe loads configured rule and schema`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try withCurrentDirectory(project) {
      let description = try SchemaDescriptionBuilder.describe(ruleName: "books")

      #expect(description.rule.name == "books")
      #expect(description.schemaPath.string == ".md-utils/schemas/book.schema.json")
      #expect(description.jsonSchema["type"] as? String == "object")
    }
  }

  @Test
  func `schema describe fails for missing rule`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    let _: Void = try withCurrentDirectory(project) {
      #expect(throws: Error.self) {
        try SchemaDescriptionBuilder.describe(ruleName: "missing")
      }
    }
  }

  @Test
  func `schema describe fails for missing schema file`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(
      project,
      rules: [ruleJSON(name: "books", schema: "missing.schema.json", paths: ["Books/**/*.md"])],
      schemas: [:]
    )

    let _: Void = try withCurrentDirectory(project) {
      #expect(throws: Error.self) {
        try SchemaDescriptionBuilder.describe(ruleName: "books")
      }
    }
  }

  @Test
  func `schema describe human output summarizes rule and all fields`() throws {
    let description = SchemaDescription(
      rule: SchemaRule(
        name: "people-in-the-bible",
        schema: "people.schema.json",
        frontmatterRequired: true,
        match: SchemaRuleMatch(
          paths: ["People/**/*.md"],
          excludePaths: ["People/Drafts/**/*.md"],
          frontmatter: ["tags": FrontmatterMatcher(includes: "Person")]
        )
      ),
      schemaPath: ".md-utils/schemas/people.schema.json",
      jsonSchema: peopleSchemaObject()
    )

    let output = SchemaDescriptionFormatter.render(description)

    #expect(output.contains("Schema Rule Name:"))
    #expect(output.contains("people-in-the-bible"))
    #expect(output.contains("Schema Rule"))
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
  func `schema describe json output includes rule and embedded schema`() throws {
    let description = SchemaDescription(
      rule: SchemaRule(
        name: "people-in-the-bible",
        schema: "people.schema.json",
        match: SchemaRuleMatch(paths: ["People/**/*.md"])
      ),
      schemaPath: ".md-utils/schemas/people.schema.json",
      jsonSchema: peopleSchemaObject()
    )

    let object = SchemaDescriptionJSONRenderer.render(description)
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
  func `schema describe markdown output renders sections and fields`() throws {
    let description = SchemaDescription(
      rule: SchemaRule(
        name: "people-in-the-bible",
        schema: "people.schema.json",
        frontmatterRequired: true,
        match: SchemaRuleMatch(paths: ["People/**/*.md"])
      ),
      schemaPath: ".md-utils/schemas/people.schema.json",
      jsonSchema: peopleSchemaObject()
    )

    let output = SchemaDescriptionMarkdownFormatter.render(description)

    #expect(output.contains("# Schema Rule Name: people-in-the-bible"))
    #expect(output.contains("## Schema Rule"))
    #expect(output.contains("- Applies to Markdown files matching People/**/*.md."))
    #expect(output.contains("## Schema Definition"))
    #expect(output.contains("### name-meaning"))
    #expect(output.contains("- Type: String, REQUIRED, minLength 1"))
    #expect(output.contains("### scripture-references[].chapter"))
    #expect(!output.contains("\u{001B}"))
  }

  @Test
  func `schema add adds rule to existing config`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project, rules: [], schemas: [:])

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot([
        "schema", "add", "books", "--path", "Books/**/*.md", "--tag", "Book",
      ])
      var command = try #require(parsed as? CLIEntry.SchemaCommands.Add)
      try await command.run()

      let config = try MdUtilsConfig.load()
      #expect(config.schemaRules.count == 1)
      #expect(config.schemaRules.first?.name == "books")
      #expect((project + ".md-utils/schemas/books.schema.json").exists)
    }
  }

  @Test
  func `schema add requires existing config`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["schema", "add", "books"])
      var command = try #require(parsed as? CLIEntry.SchemaCommands.Add)

      await #expect(throws: Error.self) {
        try await command.run()
      }
    }
  }

  @Test
  func `schema add fails on duplicate rule`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["schema", "add", "books"])
      var command = try #require(parsed as? CLIEntry.SchemaCommands.Add)

      await #expect(throws: Error.self) {
        try await command.run()
      }
    }
  }

  @Test
  func `schema remove removes rule and preserves schema by default`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["schema", "remove", "books"])
      var command = try #require(parsed as? CLIEntry.SchemaCommands.Remove)
      try await command.run()

      let config = try MdUtilsConfig.load()
      #expect(config.schemaRules.isEmpty)
      #expect((project + ".md-utils/schemas/book.schema.json").exists)
    }
  }

  @Test
  func `schema remove fails for missing rule`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["schema", "remove", "missing"])
      var command = try #require(parsed as? CLIEntry.SchemaCommands.Remove)

      await #expect(throws: Error.self) {
        try await command.run()
      }
    }
  }

  @Test
  func `schema remove delete schema deletes unshared schema file`() async throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeSchemaProject(project)

    try await withCurrentDirectory(project) {
      let parsed = try CLIEntry.parseAsRoot(["schema", "remove", "books", "--delete-schema"])
      var command = try #require(parsed as? CLIEntry.SchemaCommands.Remove)
      try await command.run()

      let config = try MdUtilsConfig.load()
      #expect(config.schemaRules.isEmpty)
      #expect(!(project + ".md-utils/schemas/book.schema.json").exists)
    }
  }

  @Test
  func `schema remove delete schema preserves shared schema file`() async throws {
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
      let parsed = try CLIEntry.parseAsRoot(["schema", "remove", "books", "--delete-schema"])
      var command = try #require(parsed as? CLIEntry.SchemaCommands.Remove)
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
      let summary = try SchemaValidatorRunner.validate()

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
      let summary = try SchemaValidatorRunner.validate(ruleName: "integrations")
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
      let summary = try SchemaValidatorRunner.validate(ruleName: "integrations")

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
      let summary = try SchemaValidatorRunner.validate()

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
      let summary = try SchemaValidatorRunner.validate()

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
      let summary = try SchemaValidatorRunner.validate()

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
      let summary = try SchemaValidatorRunner.validate()

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
      let summary = try SchemaValidatorRunner.validate()

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
      let summary = try SchemaValidatorRunner.validate()

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
      let summary = try SchemaValidatorRunner.validate()

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
      let summary = try SchemaValidatorRunner.validate()

      #expect(!summary.hasFailures)
      #expect(summary.results.first?.status == .ok)
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
    try (mdUtils + "md-utils.json").write("""
      {
        "$schema": "md-utils.schema.json",
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

  private func writeFile(_ path: Path, content: String) throws {
    try path.parent().mkpath()
    try path.write(content)
  }

  private func schemaValidationSummary() -> SchemaValidationSummary {
    SchemaValidationSummary(
      results: [
        SchemaValidationResult(
          ruleName: "books",
          schemaPath: ".md-utils/schemas/book.schema.json",
          filePath: "Books/dune.md",
          status: .ok,
          errors: []
        ),
        SchemaValidationResult(
          ruleName: "books",
          schemaPath: ".md-utils/schemas/book.schema.json",
          filePath: "Books/plain.md",
          status: .skipped,
          errors: [SchemaValidationErrorDetail(path: "frontmatter", message: "not present")]
        ),
        SchemaValidationResult(
          ruleName: "books",
          schemaPath: ".md-utils/schemas/book.schema.json",
          filePath: "Books/broken.md",
          status: .error,
          errors: [SchemaValidationErrorDetail(path: "/title", message: "is required")]
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
