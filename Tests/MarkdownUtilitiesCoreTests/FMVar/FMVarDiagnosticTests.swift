import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("fm-var diagnostics and edits")
struct FMVarDiagnosticTests {
  @Test
  func `diagnostic code constants occupy the stable namespace`() {
    let codes = diagnosticCodes()

    #expect(codes.count == Set(codes).count)
    #expect(codes.allSatisfy { $0.rawValue.hasPrefix("fm-var.") })
  }

  @Test
  func `diagnostic codes preserve future namespaced values`() throws {
    let futureCode = FMVarDiagnosticCode(rawValue: "fm-var.future.example")

    try expectRoundTrip(futureCode)
    #expect(futureCode.rawValue == "fm-var.future.example")
  }

  @Test
  func `diagnostics sort by location severity code and ordinal`() throws {
    let sourceMap = FMVarSourceMap(source: "abcdef")
    let early = try sourceMap.range(fromUTF8Offset: 1, toUTF8Offset: 2)
    let late = try sourceMap.range(fromUTF8Offset: 4, toUTF8Offset: 5)
    let values = [
      FMVarDiagnostic(
        code: .staleCache,
        severity: .warning,
        range: late,
        message: "late"
      ),
      FMVarDiagnostic(
        code: .staleCache,
        severity: .warning,
        range: early,
        elementOrdinal: 1,
        message: "warning"
      ),
      FMVarDiagnostic(
        code: .unresolvedZeroResult,
        severity: .error,
        range: early,
        elementOrdinal: 0,
        message: "error"
      ),
    ]

    #expect(values.sorted().map(\.message) == ["error", "warning", "late"])
    for value in values {
      try expectRoundTrip(value)
    }
  }

  @Test
  func `edits sort deterministically and use explicit wire keys`() throws {
    let sourceMap = FMVarSourceMap(source: "abcdef")
    let early = FMVarTextEdit(
      range: try sourceMap.range(fromUTF8Offset: 1, toUTF8Offset: 2),
      replacement: "x",
      elementOrdinal: 0
    )
    let late = FMVarTextEdit(
      range: try sourceMap.range(fromUTF8Offset: 4, toUTF8Offset: 5),
      replacement: "y",
      elementOrdinal: 1
    )

    #expect([late, early].sorted() == [early, late])
    try expectRoundTrip(early)
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(early)) as? [String: Any]
    )
    #expect(object["element-ordinal"] as? Int == 0)
  }

  private func diagnosticCodes() -> [FMVarDiagnosticCode] {
    [
      .missingAttribute, .duplicateAttribute, .unknownAttribute, .invalidAttribute,
      .invalidPlacement, .missingClosingTag, .malformedTag, .unexpectedClosingTag,
      .mismatchedClosingTag, .nestedElement, .invalidContent, .invalidSourceReference,
      .sourceAccessDenied, .sourceOutsideAllowedRoot, .sourceSymlinkEscape,
      .unsupportedSource, .sourceNotFound, .unreadableSource, .excessiveSourceSize,
      .invalidQueryArgument,
      .invalidQuery, .unsupportedQueryCapability, .queryResourceLimitExceeded,
      .unresolvedZeroResult, .unresolvedNullResult, .wrongNodelistCardinality,
      .wrongValueShape, .unsupportedItemShape, .coercionFailed, .missingScalarSourceAssociation,
      .invalidFormat, .incompatibleFormat, .missingLocale, .formattingFailed,
      .unsupportedCharacter, .staleCache,
    ]
  }

  private func expectRoundTrip<Value>(_ value: Value) throws
  where Value: Codable & Equatable {
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(Value.self, from: data)
    #expect(decoded == value)
  }
}
