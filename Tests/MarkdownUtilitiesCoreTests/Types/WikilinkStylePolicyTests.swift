import Foundation
import Testing
@testable import MarkdownUtilitiesCore

struct WikilinkStylePolicyTests {
  private func schema(_ styles: [String], _ ext: String = "either") -> JSONValue {
    .object([
      "type": .string("string"), "format": .string("Wikilink/Obsidian"),
      "wikilink": .object([
        "styles": .array(styles.map(JSONValue.string)), "markdownExtension": .string(ext),
      ]),
    ])
  }

  private func assess(_ text: String, _ property: JSONValue, advisory: Bool = false) async throws -> MarkdownTypeAssessment {
    let source = MarkdownJSONSchemaSource.inline(.object(["properties": .object(["link": property])]))
    let definition = MarkdownTypeDefinition(
      typeSchemaVersion: "2", name: .init(rawValue: "Links"), version: "1",
      frontmatter: .init(schemas: advisory ? [] : [source], recommendedSchemas: advisory ? [source] : []),
      requires: ["wikilink-constraints"],
    )
    return try await MarkdownTypeChecker(registry: .init(definitions: [definition])).assess(
      .init(content: "---\nlink: '\(text)'\n---\n"), as: "Links",
    )
  }

  @Test(arguments: [
    ("[[Alice]]", "name"), ("[[Alice.md]]", "name"),
    ("[[People/Alice.markdown]]", "vault-path"), ("[[People/Alice]]", "vault-path"),
    ("![[People/photo.png#Heading|Display]]", "vault-path"),
    ("[[./Alice]]", "relative-path"), ("[[../Alice.md]]", "relative-path"),
    ("[[#Heading]]", "self-anchor"), ("![[#^block|Label]]", "self-anchor"),
  ])
  func styles(_ sample: (String, String)) async throws {
    for style in ["name", "vault-path", "relative-path", "self-anchor"] {
      let result = try await assess(sample.0, schema([style]))
      #expect(result.conforms == (style == sample.1))
      if style != sample.1 {
        #expect(result.diagnostics.contains { $0.reason == "wikilink-style" && $0.location == "/link" })
      }
    }
  }

  @Test(arguments: [
    ("[[Alice.MD]]", true), ("[[People/Alice.MarkDown#h|a]]", true),
    ("[[Alice]]", false), ("[[photo.png]]", false), ("[[#Heading.md]]", false),
  ])
  func extensions(_ sample: (String, Bool)) async throws {
    for policy in ["require", "omit", "either"] {
      let result = try await assess(sample.0, schema(["name", "vault-path", "self-anchor"], policy))
      #expect(result.conforms == (policy == "either" || (policy == "require") == sample.1))
    }
  }

  @Test func compositionAndDiagnostics() async throws {
    let name = schema(["name"], "omit")
    let path = schema(["vault-path"], "require")
    let alternatives: JSONValue = .object(["anyOf": .array([name, path])])
    #expect(try await assess("[[Alice]]", alternatives).conforms)
    #expect(try await assess("[[People/Alice.md]]", alternatives).conforms)
    #expect(try await assess("[[Alice.md]]", alternatives).conforms == false)
    #expect(try await assess("[[Alice.md]]", .object(["not": name])).conforms)
    let advisory = try await assess("[[Alice.md]]", name, advisory: true)
    #expect(advisory.conforms)
    #expect(advisory.advisories.contains { $0.reason == "wikilink-extension" })
    let failed = try await assess("[[Alice.md]]", schema(["vault-path"], "omit"))
    #expect(Set(failed.diagnostics.compactMap(\.reason)) == ["wikilink-style", "wikilink-extension"])
    #expect(failed.diagnostics.allSatisfy { $0.schemaLocation?.contains("/wikilink/") == true })
    let reference: JSONValue = .object([
      "$defs": .object(["link": path]), "$ref": .string("#/properties/link/$defs/link"),
    ])
    #expect(try await assess("[[Alice]]", reference).conforms == false)
    #expect(try await assess("[[People/Alice.md]]", reference).conforms)
  }

  @Test func loadedGraphGateAndLegacyIsolation() throws {
    let provider = StyleSchemaProvider(schema: .object(["properties": .object(["link": schema(["vault-path"])])]))
    var definition = MarkdownTypeDefinition(
      typeSchemaVersion: "2", name: .init(rawValue: "Links"), version: "1",
      frontmatter: .init(recommendedSchemas: [.reference("links.json")]),
    )
    #expect(throws: MarkdownTypeDefinitionError.self) {
      try MarkdownTypeRegistry(definitions: [definition], schemaProvider: provider)
    }
    definition.requires = ["wikilink-constraints"]
    #expect(throws: Never.self) { try MarkdownTypeRegistry(definitions: [definition], schemaProvider: provider) }
    definition.requires = []
    definition.typeSchemaVersion = "1"
    definition.frontmatter = .init(schemas: [.reference("links.json")])
    #expect(throws: Never.self) { try MarkdownTypeRegistry(definitions: [definition], schemaProvider: provider) }
  }

  @Test func indexedDiagnosticsAndPreservation() throws {
    let source = "![[People/Alice.md#^block|Alice]]"
    let link = try Wikilink.parse(source, context: .standard)
    let policy = try WikilinkStylePolicy(.object(["styles": .array([.string("vault-path")])]), path: "#")
    #expect(policy.failures(link).isEmpty)
    #expect(link.rawValue == source)
    let property: JSONValue = .object(["type": .string("array"), "items": schema(["vault-path"], "omit")])
    let diagnostic = try SemanticSchemaDiagnostics(
      root: property, instance: .array([.string("[[People/Alice]]"), .string("[[Alice.md]]")]),
      nativePaths: [], severity: .error, constraint: "Links", source: "links.json",
    ).explain()
    #expect(diagnostic.count == 2)
    #expect(diagnostic.allSatisfy { $0.location == "/1" && $0.definitionSource == "links.json" })
  }

  @Test func invalidDeclarationsAndGates() throws {
    for policy: JSONValue in [
      .object(["styles": .array([])]),
      .object(["styles": .array([.string("name"), .string("name")])]),
      .object(["styles": .array([.string("abs-path")])]),
      .object(["styles": .array([.string("self")])]),
      .object(["markdownExtension": .string("auto")]),
      .object(["extra": .boolean(true)]),
      .object(["styles": .array([.string("self-anchor")]), "markdownExtension": .string("require")]),
    ] {
      #expect(throws: MarkdownTypeDefinitionError.self) { try WikilinkStylePolicy(policy, path: "#") }
    }
    #expect(throws: MarkdownTypeDefinitionError.self) { try SemanticSchemaAdapter.check(schema(["name"])) }
    for names in [["document-relationships"], ["unknown"], ["wikilink-constraints", "wikilink-constraints"]] {
      #expect(throws: MarkdownTypeDefinitionError.self) { try MarkdownTypeRegistry.checkCapabilities(names, version: "2") }
    }
    let decoded = try MarkdownTypeDefinitionDecoder.decode("""
      md-utils-type-schema: '2'
      requires: [wikilink-constraints]
      name: Links
      version: '1'
      frontmatter: {}
      body: {requirements: [], recommendations: []}
      context: {requirements: [], recommendations: []}
      """, format: .yaml)
    #expect(decoded.requires == ["wikilink-constraints"])
  }

  @Test func capabilityDecodeAndExportCompatibility() throws {
    let original = ResolvedMarkdownTypeFrontmatterSchema(
      name: .init(rawValue: "Legacy"), version: "1", presence: nil, schemas: [],
    )
    let encoded = try JSONEncoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "requires")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(ResolvedMarkdownTypeFrontmatterSchema.self, from: legacy) == original)

    for requires in ["null", "true", "{}", "[true]", "[1]", "['unknown']", "['wikilink-constraints', 'wikilink-constraints']"] {
      #expect(throws: MarkdownTypeDefinitionError.self) {
        try MarkdownTypeDefinitionDecoder.decode("""
          md-utils-type-schema: '2'
          requires: \(requires)
          name: Links
          version: '1'
          frontmatter: {}
          body: {requirements: [], recommendations: []}
          context: {requirements: [], recommendations: []}
          """, format: .yaml)
      }
    }
    var current = original
    current.typeSchemaVersion = "2"
    current.requires = ["wikilink-constraints"]
    #expect(try JSONDecoder().decode(ResolvedMarkdownTypeFrontmatterSchema.self, from: JSONEncoder().encode(current)) == current)
  }

  @Test func defaultsAndTomlAreLexicalAndReadOnly() async throws {
    let property: JSONValue = .object([
      "type": .string("string"), "format": .string("Wikilink"), "wikilink": .object([:]),
    ])
    #expect(try await assess("[[#Heading]]", property).conforms)
    #expect(try await assess("[[Alice.md]]", property).conforms)
    let definition = MarkdownTypeDefinition(
      typeSchemaVersion: "2", name: .init(rawValue: "Links"), version: "1",
      frontmatter: .init(schemas: [.inline(.object(["properties": .object(["link": schema(["vault-path"], "require")])]))]),
      requires: ["wikilink-constraints"],
    )
    let checker = MarkdownTypeChecker(registry: try .init(definitions: [definition]))
    let text = "+++\nlink = '![[Missing/Note.markdown#Heading|Alias]]'\n+++\nBody\n"
    let document = MarkdownRecord(content: text)
    #expect(try await checker.assess(document, as: "Links").conforms)
    #expect(document.content == text)
  }

  @Test(arguments: [
    "[[/Notes/Alice.md]]", "[[C:/Notes/Alice.md]]",
    #"[[C:\Notes\Alice.md]]"#, #"[[\\server\share\Alice.md]]"#,
  ])
  func absolutePathsDoNotMasqueradeAsSupportedStyles(_ source: String) async throws {
    #expect(try await assess(source, schema(["name", "vault-path", "relative-path", "self-anchor"])).conforms == false)
  }
}

private struct StyleSchemaProvider: MarkdownSchemaResourceProvider {
  let schema: JSONValue
  func resource(reference: String, relativeTo source: String?) throws -> MarkdownSchemaResource {
    .init(source: "https://example.invalid/links.json", schema: schema)
  }
}
