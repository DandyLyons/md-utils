import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("fm-var domain models")
struct FMVarModelTests {
  @Test
  func `round trips lossless element and declaration models`() throws {
    let sourceMap = FMVarSourceMap(source: "<fm-var key=\"title\" disabled>old</fm-var>")
    let attribute = FMVarRawAttribute(
      rawText: "key=\"title\"",
      name: "key",
      value: "title",
      quoteStyle: .double,
      range: try sourceMap.range(fromUTF8Offset: 8, toUTF8Offset: 19),
      nameRange: try sourceMap.range(fromUTF8Offset: 8, toUTF8Offset: 11),
      valueRange: try sourceMap.range(fromUTF8Offset: 13, toUTF8Offset: 18)
    )
    let secondAttribute = FMVarRawAttribute(
      rawText: "disabled",
      name: "disabled",
      range: try sourceMap.range(fromUTF8Offset: 20, toUTF8Offset: 28),
      nameRange: try sourceMap.range(fromUTF8Offset: 20, toUTF8Offset: 28)
    )
    let element = FMVarElement(
      kind: .variable,
      ordinal: 0,
      attributes: [attribute, secondAttribute],
      range: try sourceMap.range(fromUTF8Offset: 0, toUTF8Offset: 41),
      openingTagRange: try sourceMap.range(fromUTF8Offset: 0, toUTF8Offset: 29),
      cacheRange: try sourceMap.range(fromUTF8Offset: 29, toUTF8Offset: 32),
      closingTagRange: try sourceMap.range(fromUTF8Offset: 32, toUTF8Offset: 41)
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
    #expect(element.attributes.map(\.rawText) == ["key=\"title\"", "disabled"])
    #expect(incompleteElement.cacheRange == nil)
    #expect(incompleteElement.closingTagRange == nil)
    try expectRoundTrip(FMVarScalarDeclaration(
      key: "title",
      source: "self",
      defaultValue: "Untitled",
      type: .string,
      format: "plain",
      locale: "en-US"
    ))
    try expectRoundTrip(FMVarListDeclaration(
      key: "items",
      source: "list.yaml",
      itemType: .integer,
      format: .conjunction,
      locale: "en-US",
      listStyle: .short
    ))
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
      "valid", "stale", "fallback", "unresolved", "invalid", "denied", "unsupported",
    ])
    #expect(FMVarElementKind.allCases.map(\.rawValue) == ["fm-var", "fm-list", "fm-format"])
    #expect(FMVarValueType.allCases.map(\.rawValue) == [
      "string", "boolean", "integer", "number", "date", "datetime", "timestamp",
    ])
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
