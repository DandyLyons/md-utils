import Testing
@testable import MarkdownUtilitiesCore

@Suite("Markdown rule configuration normalization")
struct MarkdownRuleConfigurationTests {
  @Test
  func `Equivalent 0_1 and 0_2 configurations normalize identically`() throws {
    let legacy = """
      {
        "configVersion": "0.1.0",
        "schemaDirectory": ".md-utils/schemas/",
        "schemaRules": [{
          "name": "books",
          "schema": "book.schema.json",
          "frontmatterRequired": true,
          "match": { "paths": ["Books/**/*.md"] }
        }]
      }
      """
    let current = """
      {
        "configVersion": "0.2.0",
        "schemaDirectory": ".md-utils/schemas/",
        "rules": [{
          "name": "books",
          "match": { "paths": ["Books/**/*.md"] },
          "checks": [{
            "type": "frontmatterSchema",
            "schema": "book.schema.json",
            "frontmatterRequired": true
          }]
        }]
      }
      """

    let legacyConfig = try MarkdownRuleConfigurationDecoder.decode(legacy)
    let currentConfig = try MarkdownRuleConfigurationDecoder.decode(current)

    #expect(legacyConfig.rules == currentConfig.rules)
    #expect(legacyConfig.schemaDirectory == currentConfig.schemaDirectory)
  }

  @Test(arguments: [
    "{ \"configVersion\": \"0.3.0\", \"rules\": [] }",
    "{ \"configVersion\": \"0.2.0\", \"rules\": [], \"unknown\": true }",
  ])
  func `Unsupported versions and unknown fields fail without normalization loss`(_ source: String) {
    #expect(throws: MarkdownRuleConfigurationError.self) {
      try MarkdownRuleConfigurationDecoder.decode(source)
    }
  }

  @Test
  func `Current configuration round trips through normalized definitions`() throws {
    let definition = MarkdownRuleDefinition(
      name: "notes",
      applicability: MarkdownRuleApplicability(
        paths: ["Notes/**/*.md"],
        requirements: [
          MarkdownRuleRequirement(
            id: "notes.match.frontmatter.published.equals",
            predicate: .frontmatterField(key: "published", operation: .equals(.boolean(true)))
          )
        ]
      ),
      checks: [
        MarkdownRuleCheck(id: "notes.check[0]", predicate: .markdown(.maxBodyWords(100)))
      ]
    )
    let configuration = MarkdownRuleConfiguration(
      configVersion: MarkdownRuleConfigurationSchemaVersion.current,
      rules: [definition]
    )

    let encoded = try MarkdownRuleConfigurationEncoder.encode(configuration)
    #expect(try MarkdownRuleConfigurationDecoder.decode(encoded) == configuration)
  }

  @Test
  func `Current configuration round trips wrapped frontmatter settings`() throws {
    let source = """
      {
        "configVersion": "0.2.1",
        "schemaDirectory": ".md-utils/schemas/",
        "rules": [],
        "frontmatter": {
          "useBuiltInPresets": false,
          "syntaxes": {
            "erb-comment": {
              "commentOpen": "<%#",
              "commentClose": "%>"
            }
          },
          "extensionMappings": {
            ".ERB": "erb-comment",
            "swift": "c-block"
          }
        }
      }
      """

    let configuration = try MarkdownRuleConfigurationDecoder.decode(source)
    let frontmatter = try #require(configuration.frontmatter)
    #expect(frontmatter.useBuiltInPresets == false)
    #expect(frontmatter.extensionMappings == ["erb": "erb-comment", "swift": "c-block"])
    #expect(frontmatter.syntax(named: "erb-comment")?.openingCommentDelimiter == "<%#")

    let encoded = try MarkdownRuleConfigurationEncoder.encode(configuration)
    #expect(try MarkdownRuleConfigurationDecoder.decode(encoded) == configuration)
  }

  @Test
  func `Rules schema version rejects wrapped frontmatter settings`() {
    let source = """
      {
        "configVersion": "0.2.0",
        "schemaDirectory": ".md-utils/schemas/",
        "rules": [],
        "frontmatter": { "useBuiltInPresets": true }
      }
      """

    #expect(throws: MarkdownRuleConfigurationError.self) {
      try MarkdownRuleConfigurationDecoder.decode(source)
    }
  }
}
