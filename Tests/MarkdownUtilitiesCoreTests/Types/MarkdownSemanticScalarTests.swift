import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("Declared semantic scalars")
struct MarkdownSemanticScalarTests {
  @Test(arguments: [
    ("Date", "2024-02-29"), ("Date", "0001-01-01"), ("Date", "9999-12-31"),
    ("LocalTime", "09:30:00"), ("LocalTime", "23:59:59.123456789"),
    ("DateTime", "2026-10-12t09:30:00z"), ("DateTime", "2026-10-12T09:30:00-00:00"),
    ("DateTime", "0001-01-01T00:00:00+23:59"), ("DateTime", "9999-12-31T23:59:59-23:59"),
    ("DateTime", "1500-02-28T00:00:00Z"),
    ("UUID", "00000000-0000-0000-0000-000000000000"),
    ("UUID", "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"),
    ("UUID", "019a1234-5678-7abc-8def-123456789abc"),
    ("Wikilink", "[[Bob]]"), ("Wikilink", "![[Bob#^block-1|Robert]]"),
    ("Wikilink", "[[#Heading]]"), ("Wikilink", "[[Bob\\|Robert]]"),
  ])
  func valid(_ sample: (String, String)) throws {
    let parsed = try MarkdownSemanticScalar.parse(sample.1, format: sample.0)
    #expect(parsed.source == sample.1)
  }

  @Test(arguments: [
    ("Date", "2023-02-29"), ("Date", "1900-02-29"), ("Date", "0000-01-01"),
    ("Date", "2026-1-02"), ("Date", "2026-10-12junk"), ("Date", " 2026-10-12"),
    ("LocalTime", "24:00:00"), ("LocalTime", "09:30"), ("LocalTime", "09:30:60"),
    ("LocalTime", "09:30:00Z"), ("LocalTime", "09:30:00."), ("LocalTime", "09:30:00.1234567890"),
    ("DateTime", "2026-10-12 09:30:00Z"), ("DateTime", "2026-10-12T09:30:00"),
    ("DateTime", "2026-10-12T09:30:00+24:00"),
    ("UUID", "019a1234-5678-2abc-8def-123456789abc"),
    ("UUID", "019a1234-5678-fabc-8def-123456789abc"),
    ("UUID", "019a1234-5678-7abc-cdef-123456789abc"),
    ("Wikilink", "See [[Bob]]"), ("Wikilink", "[[Bob]] plus [[Alice]]"),
    ("Wikilink", "[[]]"), ("Wikilink", "[[ ]]"), ("Wikilink", "[[#]]"),
    ("Wikilink", "[[Bob#^]]"), ("Wikilink", "[[Bob\nAlice]]"),
  ])
  func invalid(_ sample: (String, String)) {
    #expect(throws: MarkdownSemanticScalarError.self) {
      try MarkdownSemanticScalar.parse(sample.1, format: sample.0)
    }
  }

  @Test func typedViews() throws {
    let suggestion = try Wikilink.suggestion(canonicalTarget: "Artificial Intelligence", alias: "AI")
    #expect(suggestion.rawValue == "[[Artificial Intelligence|AI]]")
    #expect(suggestion.target == "Artificial Intelligence")
    let link = try Wikilink.parse("![[People/Bob#^abc-1\\|Robert]]", context: .markdownTable)
    #expect(link.target == "People/Bob")
    #expect(link.displayText == "Robert")
    #expect(link.anchor == .blockID("abc-1"))
    #expect(link.isEmbed)
    let scalar = try MarkdownSemanticScalar.parse("2026-10-12T09:30:00.123456789-00:00", format: "DateTime")
    guard case .dateTime(_, let components, let offset, let unknown) = scalar.value else {
      Issue.record("Expected timestamp"); return
    }
    #expect(components.nanosecond == 123456789)
    #expect(offset == 0)
    #expect(unknown)
    let generated = MarkdownSemanticScalar.generateUUID().uuidString
    #expect(generated[generated.index(generated.startIndex, offsetBy: 14)] == "4")
    #expect(throws: Never.self) { try MarkdownSemanticScalar.parse(generated, format: "UUID") }
  }

  @Test func compositionAndNativeKinds() async throws {
    let nullable: JSONValue = .object(["anyOf": .array([
      .object(["type": .string("string"), "format": .string("Date")]),
      .object(["type": .string("null")]),
    ])])
    #expect(try await assess("date: null", property: nullable).conforms)
    #expect(try await assess("date: '2024-02-29'", property: nullable).conforms)
    #expect(try await assess("date: '2023-02-29'", property: nullable).conforms == false)
    #expect(try await assess("date: 2024-02-29", property: nullable).conforms == false)
    #expect(try await assess("date: ''", property: nullable).conforms == false)
    #expect(try await assess("other: true", property: nullable).conforms)
    let negated: JSONValue = .object(["not": nullable])
    #expect(try await assess("date: 'bad'", property: negated).conforms)
    #expect(try await assess("date: '2024-02-29'", property: negated).conforms == false)
    let overlapping: JSONValue = .object(["oneOf": .array([
      nullable, .object(["type": .string("string")]),
    ])])
    #expect(try await assess("date: 'bad'", property: overlapping).conforms)
    #expect(try await assess("date: '2024-02-29'", property: overlapping).conforms == false)
    let conditional: JSONValue = .object([
      "if": .object(["type": .string("string"), "format": .string("Date")]),
      "then": .boolean(false), "else": .boolean(true),
    ])
    #expect(try await assess("date: 'bad'", property: conditional).conforms)
    #expect(try await assess("date: '2024-02-29'", property: conditional).conforms == false)
    let contains: JSONValue = .object(["contains": .object(["type": .string("string"), "format": .string("Date")])])
    #expect(try await assess("date: ['bad', '2024-02-29']", property: contains).conforms)
    #expect(try await assess("date: ['bad', '2023-02-29']", property: contains).conforms == false)
  }

  @Test func advisoriesAndConfiguration() async throws {
    let date: JSONValue = .object(["type": .string("string"), "format": .string("Date")])
    let advisory = try await assess("date: 'bad'", property: date, recommended: true)
    #expect(advisory.conforms)
    #expect(advisory.advisories.isEmpty == false)
    for format in ["Time", "DateTime/ISO8601", "Date/unknown", "Unknown", "UUID/"] {
      #expect(throws: MarkdownTypeDefinitionError.self) {
        try SemanticSchemaAdapter.check(.object(["type": .string("string"), "format": .string(format)]))
      }
    }
    #expect(throws: MarkdownTypeDefinitionError.self) {
      try SemanticSchemaAdapter.check(.object(["format": .string("Date")]))
    }
  }

  @Test func indexedPathsAndBranchCauses() async throws {
    let links: JSONValue = .object([
      "type": .string("array"), "items": .object(["type": .string("string"), "format": .string("Wikilink")]),
    ])
    let result = try await assess("date: ['[[Bob]]', 'See [[Alice]]', '[[Carol]] trailing']", property: links)
    let failures = result.diagnostics.filter { $0.code == "frontmatter.format.invalid" }
    #expect(failures.map(\.location) == ["/date/1", "/date/2"])
    #expect(failures.map(\.reason) == ["syntax", "trailing-input"])
    #expect(failures.allSatisfy { $0.schemaLocation == "#/properties/date/items/format" })
    let nullable: JSONValue = .object(["anyOf": .array([
      .object(["type": .string("string"), "format": .string("Date")]),
      .object(["type": .string("null")]),
    ])])
    let invalid = try await assess("date: '2023-02-29'", property: nullable)
    #expect(invalid.diagnostics.first?.causes?.first?.reason == "calendar-range")
  }

  @Test func localReferencesAndLiteralData() async throws {
    let date: JSONValue = .object(["type": .string("string"), "format": .string("Date")])
    let property: JSONValue = .object([
      "$defs": .object(["calendar": date]),
      "$ref": .string("#/properties/date/$defs/calendar"),
      "examples": .array([.object(["format": .string("NotAFormat")])]),
    ])
    #expect(try await assess("date: '2024-02-29'", property: property).conforms)
    let failed = try await assess("date: '2023-02-29'", property: property)
    #expect(failed.conforms == false)
    #expect(failed.diagnostics.contains { $0.code == "frontmatter.format.invalid" })
  }

  @Test func tomlNativeKinds() async throws {
    let definition = MarkdownTypeDefinition(
      typeSchemaVersion: "2", name: .init(rawValue: "Scalar"), version: "1",
      frontmatter: .init(schemas: [.inline(.object([
        "properties": .object(["date": .object(["type": .string("string"), "format": .string("Date")])]),
      ]))]),
    )
    let checker = MarkdownTypeChecker(registry: try .init(definitions: [definition]))
    let native = try await checker.assess(.init(content: "+++\ndate = 2024-02-29\n+++\n"), as: "Scalar")
    #expect(native.conforms == false)
    #expect(native.diagnostics.contains { $0.reason == "native-kind" })
    #expect(try await checker.assess(.init(content: "+++\ndate = '2024-02-29'\n+++\n"), as: "Scalar").conforms)
  }

  private func assess(
    _ yaml: String,
    property: JSONValue,
    recommended: Bool = false,
  ) async throws -> MarkdownTypeAssessment {
    let source = MarkdownJSONSchemaSource.inline(.object([
      "type": .string("object"), "properties": .object(["date": property]),
    ]))
    let definition = MarkdownTypeDefinition(
      typeSchemaVersion: "2", name: .init(rawValue: "Scalar"), version: "1",
      frontmatter: .init(schemas: recommended ? [] : [source], recommendedSchemas: recommended ? [source] : []),
    )
    let checker = MarkdownTypeChecker(registry: try .init(definitions: [definition]))
    return try await checker.assess(.init(content: "---\n\(yaml)\n---\n"), as: "Scalar")
  }

  @Test func referencedFormatsAndVersionIsolation() async throws {
    let schema: JSONValue = .object([
      "$defs": .object(["date": .object(["type": .string("string"), "format": .string("Date")])]),
      "properties": .object(["a/b~c": .object(["$ref": .string("#/$defs/date")])]),
    ])
    let definition = MarkdownTypeDefinition(
      typeSchemaVersion: "2", name: .init(rawValue: "External"), version: "1",
      frontmatter: .init(schemas: [.reference("date.json")]), source: "file:///types/example.mdtype.json",
    )
    let registry = try MarkdownTypeRegistry(definitions: [definition], schemaProvider: ScalarSchemaProvider(schema: schema))
    let checker = MarkdownTypeChecker(registry: registry)
    let result = try await checker.assess(.init(content: "---\na/b~c: '2023-02-29'\n---\n"), as: "External")
    let diagnostic = try #require(result.diagnostics.first { $0.code == "frontmatter.format.invalid" })
    #expect(diagnostic.location == "/a~1b~0c")
    #expect(diagnostic.definitionSource == definition.source)
    #expect(diagnostic.schemaLocation == "https://example.invalid/date.json#/$defs/date/format")
    var legacy = definition
    legacy.typeSchemaVersion = "1"
    // v1 preserves its existing engine behavior and does not reserve the namespace.
    #expect(throws: Never.self) {
      try MarkdownTypeRegistry(definitions: [legacy], schemaProvider: ScalarSchemaProvider(schema: .object([
        "type": .string("string"), "format": .string("FutureFormat"),
      ])))
    }
  }

  @Test func unsupportedCapabilitiesFailBeforeAssessment() {
    for schema: JSONValue in [
      .object(["$ref": .string("#")]),
      .object(["$schema": .string("http://json-schema.org/draft-07/schema#")]),
      .object(["unevaluatedProperties": .boolean(false)]),
      .object([
        "extensionSchema": .object(["type": .string("string"), "format": .string("Date")]),
        "not": .object(["$ref": .string("#/extensionSchema")]),
      ]),
    ] {
      #expect(throws: MarkdownTypeDefinitionError.self) {
        try MarkdownTypeRegistry(definitions: [.init(
          typeSchemaVersion: "2", name: .init(rawValue: "Unsupported"), version: "1",
          frontmatter: .init(schemas: [.inline(schema)]),
        )])
      }
    }
  }

  @Test(arguments: [1, 3, 4, 5, 6, 7, 8])
  func standardizedUUIDVersions(_ version: Int) throws {
    let source = "019a1234-5678-\(version)abc-8def-123456789abc"
    #expect(try MarkdownSemanticScalar.parse(source, format: "UUID/RFC9562").source == source)
  }
}

private struct ScalarSchemaProvider: MarkdownSchemaResourceProvider {
  var schema: JSONValue
  func resource(reference: String, relativeTo source: String?) throws -> MarkdownSchemaResource {
    .init(source: "https://example.invalid/date.json", schema: schema)
  }
}
