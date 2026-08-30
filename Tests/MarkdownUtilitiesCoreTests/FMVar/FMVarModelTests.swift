import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("fm-var domain models")
struct FMVarModelTests {
  @Test
  func `round trips lossless element and declaration models`() throws {
    let sourceMap = FMVarSourceMap(source: "<fm-var query=\"$.title\" disabled>old</fm-var>")
    let attribute = FMVarRawAttribute(
      rawText: "query=\"$.title\"",
      name: "query",
      value: "$.title",
      quoteStyle: .double,
      range: try sourceMap.range(fromUTF8Offset: 8, toUTF8Offset: 23),
      nameRange: try sourceMap.range(fromUTF8Offset: 8, toUTF8Offset: 13),
      valueRange: try sourceMap.range(fromUTF8Offset: 15, toUTF8Offset: 22)
    )
    let secondAttribute = FMVarRawAttribute(
      rawText: "disabled",
      name: "disabled",
      range: try sourceMap.range(fromUTF8Offset: 24, toUTF8Offset: 32),
      nameRange: try sourceMap.range(fromUTF8Offset: 24, toUTF8Offset: 32)
    )
    let element = FMVarElement(
      kind: .variable,
      ordinal: 0,
      attributes: [attribute, secondAttribute],
      range: try sourceMap.range(fromUTF8Offset: 0, toUTF8Offset: 45),
      openingTagRange: try sourceMap.range(fromUTF8Offset: 0, toUTF8Offset: 33),
      cacheRange: try sourceMap.range(fromUTF8Offset: 33, toUTF8Offset: 36),
      closingTagRange: try sourceMap.range(fromUTF8Offset: 36, toUTF8Offset: 45)
    )

    try expectRoundTrip(element)
    let incompleteElement = FMVarElement(
      kind: .format,
      ordinal: 1,
      attributes: [],
      range: try sourceMap.range(fromUTF8Offset: 0, toUTF8Offset: 20),
      openingTagRange: try sourceMap.range(fromUTF8Offset: 0, toUTF8Offset: 20)
    )
    try expectRoundTrip(incompleteElement)
    #expect(element.attributes.map(\.rawText) == ["query=\"$.title\"", "disabled"])
    #expect(incompleteElement.cacheRange == nil)
    #expect(incompleteElement.closingTagRange == nil)
    let scalarDeclaration = FMVarScalarDeclaration(
      query: "$.title",
      source: "self",
      defaultZero: "Untitled",
      defaultNull: "Unknown",
      type: .string,
      format: "plain",
      locale: "en-US"
    )
    let listDeclaration = FMVarListDeclaration(
      query: "$.items",
      source: "list.yaml",
      defaultZero: "No items",
      defaultNull: "Unknown items",
      itemType: .integer,
      format: .conjunction,
      locale: "en-US",
      listStyle: .short
    )
    try expectRoundTrip(scalarDeclaration)
    try expectRoundTrip(listDeclaration)

    let scalarObject = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(scalarDeclaration)) as? [String: Any]
    )
    #expect(scalarObject["query"] as? String == "$.title")
    #expect(scalarObject["default-zero"] as? String == "Untitled")
    #expect(scalarObject["default-null"] as? String == "Unknown")
    #expect(scalarObject["key"] == nil)
    #expect(scalarObject["default"] == nil)

    let listObject = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(listDeclaration)) as? [String: Any]
    )
    #expect(listObject["query"] as? String == "$.items")
    #expect(listObject["default-zero"] as? String == "No items")
    #expect(listObject["default-null"] as? String == "Unknown items")
  }

  @Test
  func `every query value kind has a stable tagged wire shape`() throws {
    let node = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$[0]"),
      value: .null
    )
    let values: [(value: FMVarQueryValue, kind: String, shape: FMVarValueShape)] = [
      (.null, "null", .null),
      (.boolean(true), "boolean", .scalar),
      (.integer(42), "integer", .scalar),
      (.number(4.25), "number", .scalar),
      (.string("value"), "string", .scalar),
      (.array([node]), "array", .sequence),
      (.object([FMVarQueryObjectMember(name: "value", node: node)]), "object", .mapping),
    ]

    for entry in values {
      try expectRoundTrip(entry.value)
      let object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(entry.value)) as? [String: Any]
      )
      #expect(object["kind"] as? String == entry.kind)
      #expect(entry.value.shape == entry.shape)
    }
  }

  @Test
  func `query argument preserves node identities source scalars order and duplicates`() throws {
    let title = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$.title"),
      value: .string("Example"),
      sourceScalar: FMVarSourceScalar(content: "\"Example\"")
    )
    let count = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$.count"),
      value: .integer(2),
      sourceScalar: FMVarSourceScalar(content: "2")
    )
    let root = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$"),
      value: .object([
        FMVarQueryObjectMember(name: "title", node: title),
        FMVarQueryObjectMember(name: "count", node: count),
      ])
    )
    let argument = FMVarQueryArgument(root: root)
    let nodelist = FMVarNodelist(nodes: [title, count, title])

    try expectRoundTrip(argument)
    try expectRoundTrip(nodelist)
    #expect(root.value.shape == .mapping)
    #expect(title.value.shape == .scalar)
    #expect(nodelist.cardinality == .multiple)
    #expect(nodelist.nodes.map(\.id.rawValue) == ["$.title", "$.count", "$.title"])

    let encoded = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(title.value)) as? [String: Any]
    )
    #expect(encoded["kind"] as? String == "string")
    #expect(encoded["value"] as? String == "Example")
  }

  @Test
  func `reference metadata distinguishes query and result outcomes`() throws {
    let metadata = FMVarReferenceResultMetadata(
      status: .wrongValueShape,
      queryArgumentStatus: .valid,
      queryEvaluationStatus: .selected,
      selectedNodeCount: 2,
      selectedValueShape: .sequence
    )

    try expectRoundTrip(metadata)
    #expect(metadata.selectedCardinality == .multiple)
    #expect(FMVarNodelistCardinality(count: 0) == .zero)
    #expect(FMVarNodelistCardinality(count: 1) == .one)

    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any]
    )
    #expect(object["query-argument-status"] as? String == "valid")
    #expect(object["query-evaluation-status"] as? String == "selected")
    #expect(object["selected-node-count"] as? Int == 2)
    #expect(object["selected-value-shape"] as? String == "sequence")
  }

  @Test
  func `round trips complete formatting vocabulary and stable origins`() throws {
    let options = completeOptions()
    let declaration = FMVarFormatDeclaration(
      targets: FMVarFormatTarget.allCases,
      options: options
    )
    let effective = FMVarEffectiveConfiguration(
      options: options,
      origins: [
        FMVarEffectiveOptionOrigin(
          option: .locale,
          origin: FMVarConfigurationOrigin(kind: .element, elementOrdinal: 2)
        ),
        FMVarEffectiveOptionOrigin(
          option: .dateStyle,
          origin: FMVarConfigurationOrigin(kind: .scopedFormat, elementOrdinal: 0)
        ),
      ]
    )

    try expectRoundTrip(declaration)
    try expectRoundTrip(effective)
    #expect(effective.origins.map(\.option) == [.dateStyle, .locale])

    let unsorted = Data(
      #"{"options":{},"origins":[{"option":"locale","origin":{"kind":"element","element-ordinal":2}},{"option":"date-style","origin":{"kind":"scoped-format","element-ordinal":0}}]}"#.utf8
    )
    let decoded = try JSONDecoder().decode(FMVarEffectiveConfiguration.self, from: unsorted)
    #expect(decoded.origins.map(\.option) == [.dateStyle, .locale])

    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any]
    )
    #expect(object["numbering-system"] as? String == "latn")
    #expect(object["fractional-second-digits"] as? Int == 3)
    #expect(object["format-matcher"] as? String == "basic")
    #expect(object["hour12"] as? Bool == false)
  }

  @Test
  func `status and element vocabularies have stable wire values`() throws {
    #expect(FMVarReferenceStatus.allCases.map(\.rawValue) == [
      "valid", "stale", "zero-result-fallback", "unresolved-zero-result",
      "null-result-fallback", "unresolved-null-result", "invalid-query-argument",
      "invalid-query", "unsupported-query", "query-resource-limited", "wrong-value-shape",
      "invalid", "denied", "unsupported",
    ])
    #expect(FMVarElementKind.allCases.map(\.rawValue) == ["fm-var", "fm-list", "fm-format"])
    #expect(FMVarValueType.allCases.map(\.rawValue) == [
      "string", "boolean", "integer", "number", "date", "datetime", "timestamp",
    ])
    #expect(FMVarQueryArgumentStatus.allCases.map(\.rawValue) == ["valid", "invalid"])
    #expect(FMVarQueryEvaluationStatus.allCases.map(\.rawValue) == [
      "not-evaluated", "selected", "invalid-query", "unsupported-capability", "resource-limited",
    ])
    #expect(FMVarValueShape.allCases.map(\.rawValue) == ["null", "scalar", "sequence", "mapping"])
  }

  private func completeOptions() -> FMVarFormatOptions {
    FMVarFormatOptions(
      locale: "en-US",
      format: "conjunction",
      listStyle: .long,
      calendar: "gregory",
      numberingSystem: "latn",
      timeZone: "UTC",
      hourCycle: "h23",
      hour12: false,
      dateStyle: "long",
      timeStyle: "medium",
      weekday: "long",
      era: "short",
      year: "numeric",
      month: "long",
      day: "2-digit",
      dayPeriod: "long",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      fractionalSecondDigits: 3,
      timeZoneName: "short",
      formatMatcher: "basic"
    )
  }

  private func expectRoundTrip<Value>(_ value: Value) throws
  where Value: Codable & Equatable {
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(Value.self, from: data)
    #expect(decoded == value)
  }
}
