import Foundation
import Parsing
import Testing

@testable import MarkdownUtilitiesCore

@Suite("fm-var lossless parser")
struct FMVarParserTests {
  @Test("parses every RFC 001 Rev 3 attribute from the conformance corpus")
  func parsesAllV1Attributes() throws {
    let root = try #require(Bundle.module.url(forResource: "FMVar", withExtension: nil))
    let inputURL = root
      .appendingPathComponent("cases")
      .appendingPathComponent("all-v1-attributes")
      .appendingPathComponent("input.md")
    let source = try String(contentsOf: inputURL, encoding: .utf8)
    let result = try FMVarParser().parse(source)

    #expect(result.isValid)
    #expect(result.elements.map(\.kind) == [.format, .variable, .list])
    #expect(result.elements[0].attributes.count == 23)
    #expect(result.elements[1].attributes.count == 7)
    #expect(result.elements[2].attributes.count == 8)

    guard case .format(let format)? = result.declaration(forElementOrdinal: 0),
      case .scalar(let scalar)? = result.declaration(forElementOrdinal: 1),
      case .list(let list)? = result.declaration(forElementOrdinal: 2)
    else {
      Issue.record("Expected normalized declarations for all three fixture elements")
      return
    }
    #expect(format.targets == [.date, .datetime, .timestamp, .array])
    #expect(format.options.fractionalSecondDigits == 3)
    #expect(format.options.hour12 == false)
    #expect(scalar.type == .timestamp)
    #expect(scalar.source == "self")
    #expect(scalar.query == "$.published")
    #expect(scalar.defaultZero == "Unknown")
    #expect(scalar.defaultNull == "Not published")
    #expect(list.format == .conjunction)
    #expect(list.listStyle == .long)
    #expect(list.query == "$.items")
    #expect(list.defaultZero == "No items")
    #expect(list.defaultNull == "Items unavailable")
  }

  @Test("parses conforming inline block and configuration elements losslessly")
  func parsesConformingElements() throws {
    let source = """
      ---
      title: Café
      names: [Alice, Bob]
      ---
      <fm-format locale="en-US"></fm-format>

      # **<fm-var  query = '$.title' locale="en-US">Café</fm-var>**

      | People |
      | --- |
      | <fm-list query="$.names" format="conjunction">Alice and Bob</fm-list> |

      <fm-list query="$.names" format="unordered">
      <ul>
      <li>Alice</li>
      <li>Bob</li>
      </ul>
      </fm-list>
      """

    var input = Substring(source)
    let result = try FMVarParser().parse(&input)

    #expect(input.isEmpty)
    #expect(result.isValid)
    #expect(result.elements.map(\.kind) == [.format, .variable, .list, .list])
    #expect(result.elements.map(\.ordinal) == [0, 1, 2, 3])
    #expect(result.declarations.count == 4)

    let scalar = try #require(result.elements[safe: 1])
    #expect(try result.text(in: scalar.range) == "<fm-var  query = '$.title' locale=\"en-US\">Café</fm-var>")
    #expect(scalar.attributes.map(\.rawText) == ["query = '$.title'", "locale=\"en-US\""])
    #expect(scalar.attributes.map(\.quoteStyle) == [.single, .double])
    #expect(scalar.attributes.map(\.value) == ["$.title", "en-US"])
  }

  @Test("cache replacement preserves every unrelated UTF-8 byte")
  func cacheReplacementIsSurgical() throws {
    let source = "é\r\nBefore <fm-var query = '$.title'>old</fm-var> after\r\n"
    let result = try FMVarParser().parse(source)
    let element = try #require(result.elements.first)
    let cache = try #require(element.cacheRange)

    #expect(try result.text(in: element.openingTagRange) == "<fm-var query = '$.title'>")
    #expect(try result.text(in: cache) == "old")
    #expect(try result.text(in: try #require(element.closingTagRange)) == "</fm-var>")

    let replacement = "nouveau ☕️"
    let updated = try result.replacingCache(ofElementOrdinal: 0, with: replacement)
    let sourceBytes = Array(source.utf8)
    let updatedBytes = Array(updated.utf8)
    #expect(updated == "é\r\nBefore <fm-var query = '$.title'>nouveau ☕️</fm-var> after\r\n")
    #expect(updatedBytes.prefix(cache.start.utf8Offset)
      .elementsEqual(sourceBytes.prefix(cache.start.utf8Offset)))
    #expect(updatedBytes.suffix(from: cache.start.utf8Offset + replacement.utf8.count)
      .elementsEqual(sourceBytes.suffix(from: cache.end.utf8Offset)))
  }

  @Test("ignores tag-like text in Markdown exclusion contexts")
  func ignoresExcludedContexts() throws {
    let source = #"""
      +++
      example = '<fm-var query="$.toml">ignored</fm-var>'
      +++

      `<fm-var query="$.inline">ignored</fm-var>`

      <!-- <fm-var query="$.comment">ignored</fm-var> -->

      ```html
      <fm-list query="$.fence" format="ordered"><ol></ol></fm-list>
      ```

          <fm-var query="$.indented">ignored</fm-var>

      <code><fm-var query="$.html-code">ignored</fm-var></code>

      \<fm-var query="$.escaped">ignored</fm-var>

      <fm-var query="$.visible">yes</fm-var>
      """#

    let result = try FMVarParser().parse(source)

    #expect(result.elements.count == 1)
    #expect(result.elements.first?.attribute(named: "query")?.value == "$.visible")
    #expect(result.diagnostics.isEmpty)
  }

  @Test("recovers after malformed and missing closing tags")
  func recoversAfterMalformedInput() throws {
    let source = """
      <fm-var query="$.broken
      <fm-var query="$.missing">old
      <fm-var query="$.valid">yes</fm-var>
      """
    let result = try FMVarParser().parse(source)

    #expect(result.elements.count == 3)
    #expect(result.elements.map(\.ordinal) == [0, 1, 2])
    #expect(result.elements[0].closingTagRange == nil)
    #expect(result.elements[1].closingTagRange == nil)
    #expect(try result.text(in: try #require(result.elements[2].cacheRange)) == "yes")
    #expect(result.declaration(forElementOrdinal: 2) != nil)
    #expect(result.diagnostics.map(\.code).contains(.malformedTag))
    #expect(result.diagnostics.map(\.code).contains(.missingClosingTag))
    #expect(result.diagnostics.map(\.code).contains(.nestedElement))
  }

  @Test("diagnoses nested overlapping and unexpected custom tags")
  func diagnosesStructuralFailures() throws {
    let source = """
      </fm-list>
      <fm-var query="$.outer"><fm-list query="$.inner" format="unit">x</fm-var></fm-list>
      """
    let result = try FMVarParser().parse(source)
    let codes = result.diagnostics.map(\.code)

    #expect(result.elements.count == 2)
    #expect(codes.contains(.unexpectedClosingTag))
    #expect(codes.contains(.nestedElement))
    #expect(codes.contains(.mismatchedClosingTag))
    #expect(codes.contains(.missingClosingTag))
  }

  @Test("diagnoses attribute syntax while retaining authored attributes")
  func diagnosesAttributes() throws {
    let source = """
      <fm-var query="$.one" query='$.two' mystery="x">old</fm-var>
      <fm-list query=$.items format="bogus">old</fm-list>
      <fm-format hour12="sometimes" fractional-second-digits="9"></fm-format>
      """
    let result = try FMVarParser().parse(source)
    let codes = result.diagnostics.map(\.code)

    #expect(result.elements[0].attributes.map(\.name) == ["query", "query", "mystery"])
    #expect(result.elements[1].attribute(named: "query")?.quoteStyle == .unquoted)
    #expect(codes.contains(.duplicateAttribute))
    #expect(codes.contains(.unknownAttribute))
    #expect(codes.contains(.invalidAttribute))
    #expect(result.declarations.isEmpty)
  }

  @Test("Rev 2 key and default attributes remain raw but are not normalized")
  func rejectsDeprecatedRev2Attributes() throws {
    let source = "<fm-var key=\"title\" default=\"Untitled\">old</fm-var>"
    let result = try FMVarParser().parse(source)

    #expect(result.elements.first?.attributes.map(\.name) == ["key", "default"])
    #expect(result.declarations.isEmpty)
    #expect(result.diagnostics.filter { $0.code == .unknownAttribute }.count == 2)
    #expect(result.diagnostics.map(\.code).contains(.missingAttribute))
  }

  @Test("decodes query attribute entities while preserving raw syntax")
  func decodesQueryAttributeEntities() throws {
    let source = #"<fm-var query="$.books[?@.price &lt; 10]">Affordable</fm-var>"#
    let result = try FMVarParser().parse(source)

    guard case .scalar(let declaration)? = result.declaration(forElementOrdinal: 0) else {
      Issue.record("Expected a normalized scalar declaration")
      return
    }
    #expect(declaration.query == "$.books[?@.price < 10]")
    #expect(
      result.elements.first?.attribute(named: "query")?.value
        == "$.books[?@.price &lt; 10]"
    )
    #expect(result.diagnostics.isEmpty)
  }

  @Test("diagnoses block-list and fm-format placement precisely")
  func diagnosesPlacement() throws {
    let source = """
      ---
      names: [A]
      ---
      Ordinary content.
      <fm-format locale="en-US"></fm-format>
      # <fm-list query="$.names" format="ordered"><ol><li>A</li></ol></fm-list>
      """
    let result = try FMVarParser().parse(source)
    let placements = result.diagnostics.filter { $0.code == .invalidPlacement }

    #expect(placements.count == 2)
    #expect(placements.map(\.elementKind).contains(.format))
    #expect(placements.map(\.elementKind).contains(.list))
  }

  @Test("validates scalar inline-list block-list and format child models")
  func diagnosesInvalidChildren() throws {
    let source = """
      <fm-var query="$.title">*raw*</fm-var>
      <fm-list query="$.names" format="unit">A & B</fm-list>
      <fm-list query="$.names" format="ordered">
      <ul><li>A</li></ul>
      </fm-list>
      <fm-var query="$.control">bad\u{0}value</fm-var>
      """
    let result = try FMVarParser().parse(source)
    let invalidContent = result.diagnostics.filter { $0.code == .invalidContent }

    #expect(invalidContent.count == 4)
    #expect(invalidContent.map(\.elementOrdinal) == [0, 1, 2, 3])
  }

  @Test("fixture cases remain language-neutral", arguments: try parserFixtureCases())
  func languageNeutralCases(testCase: FMVarParserFixtureCase) throws {
    let result = try FMVarParser().parse(testCase.source)
    #expect(result.elements.map(\.kind.rawValue) == testCase.elementKinds)
    #expect(result.diagnostics.map(\.code.rawValue) == testCase.diagnosticCodes)
  }
}

struct FMVarParserFixtureCase: Decodable, Sendable {
  let id: String
  let source: String
  let elementKinds: [String]
  let diagnosticCodes: [String]

  private enum CodingKeys: String, CodingKey {
    case id
    case source
    case elementKinds = "element-kinds"
    case diagnosticCodes = "diagnostic-codes"
  }
}

private struct FMVarParserFixtureCorpus: Decodable {
  let schemaVersion: Int
  let cases: [FMVarParserFixtureCase]

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema-version"
    case cases
  }
}

private func parserFixtureCases() throws -> [FMVarParserFixtureCase] {
  let root = try #require(Bundle.module.url(forResource: "FMVar", withExtension: nil))
  let url = root.appendingPathComponent("parser-cases.json")
  let corpus = try JSONDecoder().decode(
    FMVarParserFixtureCorpus.self,
    from: Data(contentsOf: url)
  )
  #expect(corpus.schemaVersion == 1)
  return corpus.cases
}

private extension Array {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
