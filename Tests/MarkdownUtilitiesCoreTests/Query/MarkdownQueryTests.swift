import Foundation
import Testing
@testable import MarkdownUtilitiesCore

struct MarkdownQueryTests {
  @Test func calendarWeeksAndSemanticProfilesKeepTheirComparisonDomains() async throws {
    let dates = try await observation("---\nday: 2026-10-26\nuuid: '550e8400-e29b-41d4-a716-446655440000'\nlink: '[[Example]]'\n---\n")
    let sunday = try MarkdownQueryPredicate(key: "day", jsonPath: nil, operation: "same-week", operand: "2026-10-25")
    let monday = try MarkdownQueryPredicate(key: "day", jsonPath: nil, operation: "same-week", operand: "2026-10-25", monday: true)
    #expect(try sunday.matches(dates))
    #expect(try monday.matches(dates) == false)
    #expect(try MarkdownQueryPredicate(key: "day", jsonPath: nil, operation: "same-month", operand: "2026-10-01").matches(dates))
    #expect(try MarkdownQueryPredicate(key: "day", jsonPath: nil, operation: "same-year", operand: "2026-01-01").matches(dates))
    #expect(try MarkdownQueryPredicate(key: "uuid", jsonPath: nil, operation: "equals", operand: "550E8400-E29B-41D4-A716-446655440000", format: "UUID", caseSensitive: true).matches(dates))
    #expect(try MarkdownQueryPredicate(key: "link", jsonPath: nil, operation: "equals", operand: "[[example]]", format: "Wikilink").matches(dates))
    let clock = try await observation("+++\nclock = 08:30:00\n+++")
    #expect(try MarkdownQueryPredicate(key: "clock", jsonPath: nil, operation: "before", operand: "09:00:00", format: "LocalTime").matches(clock))
  }

  @Test func wildcardQuantifiersAndNullPresenceRemainDistinct() async throws {
    let record = try await observation("---\nauthors: [{name: Dan}, {name: Other}, {}]\nvalue: null\n---\n")
    #expect(try MarkdownQueryPredicate(key: nil, jsonPath: "$.authors[*].name", operation: "equals", operand: "Dan").matches(record))
    #expect(try MarkdownQueryPredicate(key: nil, jsonPath: "$.authors[*].name", operation: "equals", operand: "Dan", all: true).matches(record) == false)
    #expect(try MarkdownQueryPredicate(key: "value", jsonPath: nil, operation: "exists", operand: nil).matches(record))
    #expect(try MarkdownQueryPredicate(key: "value", jsonPath: nil, operation: "is-null", operand: nil).matches(record))
    #expect(try MarkdownQueryPredicate(key: "absent", jsonPath: nil, operation: "is-null", operand: nil).matches(record) == false)
  }
  @Test func yamlTimestampSpellingKeepsNativeSemantics() async throws {
    let record = try await observation("---\ncreated: 2026-10-28 3:04:05.123456789 -5\n---\n")
    let query = try MarkdownQueryPredicate(key: "created", jsonPath: nil, operation: "equals", operand: "2026-10-28T08:04:05.123456789Z", format: "DateTime")
    #expect(try query.matches(record))
  }
  private func observation(_ content: String) async throws -> MarkdownSurveyObservation {
    try await .read(MarkdownRecord(content: content, context: .init(path: try MarkdownRecordPath("note.md"))))
  }

  @Test(arguments: ["any", "all"])
  func emptySelectionNeverMatches(mode: String) async throws {
    let record = try await observation("---\nauthors: []\n---\n")
    let query = try MarkdownQueryPredicate(key: nil, jsonPath: "$.authors[*].name", operation: "not-equals", operand: "Dan", all: mode == "all")
    #expect(try query.matches(record) == false)
  }

  @Test func numericComparisonPreservesLargeIntegers() async throws {
    let record = try await observation("---\nn: 9007199254740993\nfloat: 3.0\ntext: '3'\n---\n")
    let exact = try MarkdownQueryPredicate(key: "n", jsonPath: nil, operation: "equals", operand: "9007199254740993", domain: "number")
    let rounded = try MarkdownQueryPredicate(key: "n", jsonPath: nil, operation: "equals", operand: "9007199254740992.0", domain: "number")
    #expect(try exact.matches(record))
    #expect(try rounded.matches(record) == false)
    let fraction = try MarkdownQueryPredicate(key: "n", jsonPath: nil, operation: "equals", operand: "9007199254740993.0", domain: "number")
    #expect(try fraction.matches(record) == false, "Fraction operands use binary64; they must not become exact integer tokens")
    #expect(try MarkdownQueryPredicate(key: "float", jsonPath: nil, operation: "equals", operand: "3", domain: "integer").matches(record))
    #expect(try MarkdownQueryPredicate(key: "text", jsonPath: nil, operation: "equals", operand: "3", domain: "integer").matches(record) == false)
    #expect(record.valueMetadata?["/float"]?.kind == "number")
  }

  @Test func nativeTOMLOffsetAndPrecisionSurviveParsing() async throws {
    let record = try await observation("+++\ncreated = 2026-10-28T23:30:00.123456789-05:00\n+++")
    #expect(record.state == .parsed)
    #expect(record.valueMetadata?["/created"]?.source == "2026-10-28T23:30:00.123456789-05:00")
    let query = try MarkdownQueryPredicate(key: "created", jsonPath: nil, operation: "equals", operand: "2026-10-29T04:30:00.123456789Z", format: "DateTime")
    #expect(try query.matches(record))
    let different = try MarkdownQueryPredicate(key: "created", jsonPath: nil, operation: "equals", operand: "2026-10-29T04:30:00.123456788Z", format: "DateTime")
    #expect(try different.matches(record) == false)
  }

  @Test func booleansUseDecoderIdentityAndStringsUseCaseFolding() async throws {
    let record = try await observation("---\nenabled: YES\nword: STRASSE\naccent: café\n---\n")
    #expect(try MarkdownQueryPredicate(key: "enabled", jsonPath: nil, operation: "equals", operand: "true", domain: "boolean").matches(record))
    #expect(try MarkdownQueryPredicate(key: "word", jsonPath: nil, operation: "equals", operand: "Straße").matches(record))
    #expect(try MarkdownQueryPredicate(key: "accent", jsonPath: nil, operation: "equals", operand: "cafe").matches(record) == false)
  }

  @Test(arguments: ["2026-03-08T02:30:00", "2026-11-01T01:30:00"])
  func dstGapsAndFoldsRemainUnknown(_ text: String) async throws {
    let record = try await observation("+++\ncreated = \(text)\n+++")
    let zone = try #require(TimeZone(identifier: "America/Chicago"))
    let query = try MarkdownQueryPredicate(key: "created", jsonPath: nil, operation: "before", operand: "2027-01-01T00:00:00Z", timezone: zone)
    #expect(throws: MarkdownQueryPredicate.Failure.self) { try query.matches(record) }
  }
}
