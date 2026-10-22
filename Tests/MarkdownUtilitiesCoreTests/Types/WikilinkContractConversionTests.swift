import Foundation
import Testing
@testable import MarkdownUtilitiesCore

struct WikilinkContractConversionTests {
  private func policy(_ styles: [String], _ ext: String = "require") -> JSONValue {
    .object(["type": .string("string"), "format": .string("Wikilink"),
      "wikilink": .object(["styles": .array(styles.map(JSONValue.string)), "markdownExtension": .string(ext)]),
    ])
  }

  private func plan(_ content: String, schema: JSONValue, paths: Set<String> = ["notes/source.md", "people/Alice.md"],
    preferences: WikilinkContractPreferences = .init(), advisory: Bool = false,
  ) async throws -> WikilinkContractPlan {
    let definition = MarkdownTypeDefinition(typeSchemaVersion: "2", name: .init(rawValue: "Links"), version: "1",
      frontmatter: .init(schemas: advisory ? [] : [.inline(schema)], recommendedSchemas: advisory ? [.inline(schema)] : []),
      requires: ["wikilink-constraints"],
    )
    return try await WikilinkContractConversion.plan(
      record: .init(content: content, context: .init(path: try MarkdownRecordPath("notes/source.md"))),
      type: "Links", registry: .init(definitions: [definition]),
      resolver: .init(paths: paths, namespaceComplete: true), preferences: preferences,
    )
  }

  private func property(_ value: JSONValue) -> JSONValue { .object(["properties": .object(["link": value])]) }

  @Test func nestedLiteralKeysAndArraysPreserveBodyAndOtherValues() async throws {
    let schema: JSONValue = .object(["properties": .object(["literal.key": .object([
      "type": .string("array"), "items": .object(["properties": .object(["a/b": policy(["relative-path"])])]),
    ])])])
    let source = "---\nliteral.key:\n  - a/b: '![[Alice#^part|Alias]]'\nother: false\n---\nBody [[Alice]]\n"
    let result = try await plan(source, schema: schema)
    #expect(result.changes.first?.path == [.key("literal.key"), .index(0), .key("a/b")])
    #expect(result.changes.first?.replacement == "![[../people/Alice.md#^part|Alias]]")
    #expect(result.proposed.content.hasSuffix("Body [[Alice]]\n"))
    let analyzed = await MarkdownRecordAnalyzer.analyze(result.proposed)
    #expect(analyzed.userFrontmatter?["other"] == .boolean(false))
  }

  @Test func ambiguityRequiresPreferencesAndConformingValuesStayByteIdentical() async throws {
    let schema = property(policy(["vault-path", "relative-path"], "either"))
    let source = "---\nlink: '[[Alice]]'\n---\n"
    let ambiguous = try await plan(source, schema: schema)
    #expect(ambiguous.unresolved)
    #expect(ambiguous.hasChanges == false)
    let selected = try await plan(source, schema: schema,
      preferences: .init(style: "relative-path", markdownExtension: "omit"))
    #expect(selected.changes.first?.replacement == "[[../people/Alice]]")
    let existing = "---\n# keep comment\nlink: '[[people/Alice.md]]'\n---\n"
    let unchanged = try await plan(existing, schema: schema, preferences: .init(style: "relative-path", markdownExtension: "omit"))
    #expect(unchanged.proposed.content == existing)
    #expect(unchanged.unresolved == false)
    let conflict = try await plan(source, schema: property(policy(["vault-path"])), preferences: .init(style: "name"))
    #expect(conflict.unresolved)
  }

  @Test func ambiguousOriginalMissingAndRootOnlyPathsNeverChange() async throws {
    for paths: Set<String> in [["notes/source.md", "Alice.md"], ["notes/source.md"], ["notes/source.md", "a/Alice.md", "b/Alice.md"]] {
      let result = try await plan("---\nlink: '[[Alice]]'\n---\n", schema: property(policy(["vault-path"])), paths: paths)
      #expect(result.unresolved)
      #expect(result.hasChanges == false)
    }
  }

  @Test func referencesAndAllOfAreMandatoryButAlternativesAreNotFlattened() async throws {
    let schema: JSONValue = .object([
      "$defs": .object(["link": policy(["vault-path"])]),
      "properties": .object(["link": .object(["allOf": .array([
        .object(["$ref": .string("#/$defs/link")]), policy(["vault-path", "relative-path"], "either"),
      ])])]),
    ])
    let source = "---\nlink: '[[Alice]]'\n---\n"
    let result = try await plan(source, schema: schema)
    #expect(result.changes.first?.replacement == "[[people/Alice.md]]")
    #expect(result.changes.first?.declarations.contains("#/$defs/link") == true)
    let alternative = property(.object(["anyOf": .array([policy(["vault-path"]), policy(["relative-path"])])]))
    #expect(try await plan(source, schema: alternative).unresolved)
    let valid = "---\nlink: '[[people/Alice.md]]'\n---\n"
    #expect(try await plan(valid, schema: alternative).unresolved == false)
    let conflicting = property(.object(["allOf": .array([policy(["vault-path"]), policy(["name"])])]))
    #expect(try await plan(source, schema: conflicting).unresolved)
  }

  @Test func alternativesCanUseNonLexicalShapeToEstablishIntent() async throws {
    let alternative = property(.object(["oneOf": .array([policy(["vault-path"]), .object(["type": .string("null")])])]))
    let result = try await plan("---\nlink: '[[Alice]]'\n---\n", schema: alternative)
    #expect(result.changes.first?.replacement == "[[people/Alice.md]]")
  }

  @Test func recommendationsAndLiteralKeyFiltersAreOptIn() async throws {
    let schema = property(policy(["vault-path"]))
    let source = "---\nlink: '[[Alice]]'\n---\n"
    #expect(try await plan(source, schema: schema, advisory: true).hasChanges == false)
    #expect(try await plan(source, schema: schema, preferences: .init(includeRecommendations: true), advisory: true).hasChanges)
    #expect(try await plan(source, schema: schema, preferences: .init(keys: ["other"])).hasChanges == false)
  }

  @Test func malformedWholeValuesAreNotScannerMatches() async throws {
    for value in ["text [[Alice]]", "[[Alice]] trailing", "not a link"] {
      let result = try await plan("---\nlink: '\(value)'\n---\n", schema: property(policy(["vault-path"])))
      #expect(result.unresolved)
      #expect(result.hasChanges == false)
    }
  }

  @Test func attachmentAndMarkdownExtensionsAndSelfAnchors() async throws {
    let attachment = try await plan("---\nlink: '![[photo.png|Photo]]'\n---\n",
      schema: property(policy(["vault-path"], "either")), paths: ["notes/source.md", "assets/photo.png"])
    #expect(attachment.changes.first?.replacement == "![[assets/photo.png|Photo]]")
    let markdown = try await plan("+++\nlink = '[[Alice]]'\n+++\nBody\n",
      schema: property(policy(["relative-path"])), paths: ["notes/source.md", "people/Alice.markdown"])
    #expect(markdown.changes.first?.replacement == "[[../people/Alice.markdown]]")
    #expect(markdown.proposed.content.hasPrefix("+++\n"))
    #expect(markdown.proposed.content.hasSuffix("Body\n"))
    let selfLink = try await plan("---\nlink: '[[notes/source.md#Heading]]'\n---\n",
      schema: property(policy(["self-anchor"], "omit")))
    #expect(selfLink.changes.first?.replacement == "[[#Heading]]")
  }

  @Test func conditionsAndNegativeOrExistentialIntentRemainConservative() async throws {
    let condition: JSONValue = .object([
      "if": .object(["properties": .object(["kind": .object(["const": .string("person")])])]),
      "then": property(policy(["vault-path"])), "else": property(policy(["relative-path"])),
    ])
    let source = "---\nkind: person\nlink: '[[Alice]]'\n---\n"
    #expect(try await plan(source, schema: condition).changes.first?.replacement == "[[people/Alice.md]]")
    let linkCondition: JSONValue = .object([
      "if": property(policy(["name"], "omit")), "then": property(policy(["vault-path"])),
    ])
    #expect(try await plan(source, schema: linkCondition).unresolved)
    let negated = property(.object(["not": policy(["name"], "omit")]))
    #expect(try await plan(source, schema: negated).unresolved)
    let contains = property(.object(["type": .string("array"), "contains": policy(["vault-path"])]))
    #expect(try await plan("---\nlink: ['[[Alice]]']\n---\n", schema: contains).unresolved)
  }

  @Test func nativeKindsAreNotCoercedAndUnsafeTargetSyntaxIsRejected() async throws {
    let scalar = property(policy(["vault-path"]))
    for value in ["123", "true", "null", "{nested: '[[Alice]]'}"] {
      let result = try await plan("---\nlink: \(value)\n---\n", schema: scalar)
      #expect(result.unresolved)
      #expect(result.hasChanges == false)
    }
    let impossible = try await plan("---\nlink: '[[Alice]]'\n---\n", schema: scalar,
      paths: ["notes/source.md", "folder#fragment/Alice.md"])
    #expect(impossible.unresolved)
    #expect(impossible.hasChanges == false)
  }
}
